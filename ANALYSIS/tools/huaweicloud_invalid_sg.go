// SPDX-License-Identifier: Apache-2.0

package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"
	"time"

	hwAPI "github.com/cilium/cilium/pkg/huaweicloud/api"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "INVALID_SG_CREATE_FAIL: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	client, err := hwAPI.NewClient(
		requiredEnv("HUAWEI_CLOUD_ACCESS_KEY"),
		requiredEnv("HUAWEI_CLOUD_SECRET_KEY"),
		requiredEnv("HUAWEI_CLOUD_PROJECT_ID"),
		requiredEnv("HUAWEI_CLOUD_REGION"),
		os.Getenv("HUAWEI_CLOUD_ENDPOINT"),
	)
	if err != nil {
		return fmt.Errorf("create client: %w", err)
	}
	if os.Getenv("AUDIT_MODE") == "verify" {
		return verifyParentSet(ctx, client, requiredEnv("POOL_RESOURCE_IDS"))
	}

	deleteID := requiredEnv("DELETE_FREE_RESOURCE_ID")
	anchor, err := client.GetSubNetworkInterface(ctx, deleteID)
	if err != nil {
		return fmt.Errorf("get anchor: %w", err)
	}
	before, err := parentIDs(ctx, client, anchor.ParentID)
	if err != nil {
		return fmt.Errorf("list baseline parent: %w", err)
	}
	beforeHash := idHash(before)
	if !containsID(before, deleteID) {
		return fmt.Errorf("delete candidate is outside anchor parent set")
	}
	if err := client.DeleteSubNetworkInterface(ctx, deleteID); err != nil {
		return fmt.Errorf("delete free SubENI: %w", err)
	}
	if err := waitNotFound(ctx, client, deleteID); err != nil {
		return err
	}
	afterDelete, err := parentIDs(ctx, client, anchor.ParentID)
	if err != nil {
		return fmt.Errorf("list parent after freeing quota: %w", err)
	}
	if len(afterDelete) != len(before)-1 || containsID(afterDelete, deleteID) {
		return fmt.Errorf("freeing one SubENI produced an unexpected parent set")
	}
	afterDeleteHash := idHash(afterDelete)

	id, _, createErr := client.CreateSubNetworkInterface(ctx, hwAPI.CreateSubENIRequest{
		TrunkInterfaceID: anchor.ParentID,
		SubnetID:         anchor.SubnetID,
		SecurityGroupIDs: []string{"00000000-0000-0000-0000-000000000000"},
		Tags:             map[string]string{"cilium-audit": "audit92-invalid-sg"},
	})
	if createErr == nil {
		if id == "" {
			return fmt.Errorf("cloud unexpectedly accepted invalid security group without returning a resource ID")
		}
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cleanupCancel()
		if cleanupErr := client.DeleteSubNetworkInterface(cleanupCtx, id); cleanupErr != nil {
			return fmt.Errorf("cloud unexpectedly accepted invalid security group and cleanup failed: %w", cleanupErr)
		}
		return fmt.Errorf("cloud unexpectedly accepted invalid security group")
	}
	errorText := strings.ToLower(createErr.Error())
	if !strings.Contains(errorText, "security") && !strings.Contains(errorText, "安全组") {
		return fmt.Errorf("cloud rejection was not attributable to security group: %v", createErr)
	}
	if !strings.Contains(errorText, "request_id:") || strings.Contains(errorText, "request_id: )") {
		return fmt.Errorf("cloud rejection lacks request ID: %v", createErr)
	}

	after, err := parentIDs(ctx, client, anchor.ParentID)
	if err != nil {
		return fmt.Errorf("list parent after rejected create: %w", err)
	}
	afterHash := idHash(after)
	if afterDeleteHash != afterHash || len(afterDelete) != len(after) {
		return fmt.Errorf("parent resource set changed after rejected create: expected=%d actual=%d", len(afterDelete), len(after))
	}

	fmt.Printf("INVALID_SG_CREATE_PASS baseline_count=%d remaining_count=%d baseline_hash=%s remaining_hash=%s request_id=present\n", len(before), len(after), beforeHash, afterHash)
	return nil
}

func waitNotFound(ctx context.Context, client *hwAPI.Client, id string) error {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		_, err := client.GetSubNetworkInterface(ctx, id)
		if errors.Is(err, hwAPI.ErrNotFound) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("wait for deleted SubENI: %w", err)
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
}

func verifyParentSet(ctx context.Context, client *hwAPI.Client, rawIDs string) error {
	expected := strings.Split(rawIDs, ",")
	for i := range expected {
		expected[i] = strings.TrimSpace(expected[i])
		if expected[i] == "" {
			return fmt.Errorf("empty expected resource ID")
		}
	}
	anchor, err := client.GetSubNetworkInterface(ctx, expected[0])
	if err != nil {
		return fmt.Errorf("get verification anchor: %w", err)
	}
	actual, err := parentIDs(ctx, client, anchor.ParentID)
	if err != nil {
		return err
	}
	sort.Strings(expected)
	if strings.Join(actual, "\n") != strings.Join(expected, "\n") {
		return fmt.Errorf("parent set mismatch: expected=%d actual=%d", len(expected), len(actual))
	}
	fmt.Printf("VERIFY_PARENT_SET_PASS count=%d hash=%s\n", len(actual), idHash(actual))
	return nil
}

func containsID(ids []string, id string) bool {
	for _, candidate := range ids {
		if candidate == id {
			return true
		}
	}
	return false
}

func parentIDs(ctx context.Context, client *hwAPI.Client, parentID string) ([]string, error) {
	items, err := client.ListSubNetworkInterfaces(ctx, parentID)
	if err != nil {
		return nil, err
	}
	ids := make([]string, 0, len(items))
	for _, item := range items {
		if item == nil || item.ID == "" {
			return nil, fmt.Errorf("list returned item without ID")
		}
		ids = append(ids, item.ID)
	}
	sort.Strings(ids)
	return ids, nil
}

func idHash(ids []string) string {
	sum := sha256.Sum256([]byte(strings.Join(ids, "\n")))
	return hex.EncodeToString(sum[:])
}

func requiredEnv(name string) string {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		fmt.Fprintf(os.Stderr, "required environment variable %s is empty\n", name)
		os.Exit(2)
	}
	return value
}
