// SPDX-License-Identifier: Apache-2.0

package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"
	"time"

	hwAPI "github.com/cilium/cilium/pkg/huaweicloud/api"
	eniTypes "github.com/cilium/cilium/pkg/huaweicloud/eni/types"
	"github.com/huaweicloud/huaweicloud-sdk-go-v3/core/auth"
	"github.com/huaweicloud/huaweicloud-sdk-go-v3/core/config"
	coreregion "github.com/huaweicloud/huaweicloud-sdk-go-v3/core/region"
	hwVPC "github.com/huaweicloud/huaweicloud-sdk-go-v3/services/vpc/v3"
	vpcmodel "github.com/huaweicloud/huaweicloud-sdk-go-v3/services/vpc/v3/model"
	hwVPCRegion "github.com/huaweicloud/huaweicloud-sdk-go-v3/services/vpc/v3/region"
)

const operationTimeout = 5 * time.Minute

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "HUAWEICLOUD_CLOUD_CRUD_FAIL: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	ctx, cancel := context.WithTimeout(context.Background(), operationTimeout)
	defer cancel()

	accessKey := requiredEnv("HUAWEI_CLOUD_ACCESS_KEY")
	secretKey := requiredEnv("HUAWEI_CLOUD_SECRET_KEY")
	projectID := requiredEnv("HUAWEI_CLOUD_PROJECT_ID")
	region := requiredEnv("HUAWEI_CLOUD_REGION")
	endpoint := os.Getenv("HUAWEI_CLOUD_ENDPOINT")
	client, err := hwAPI.NewClient(accessKey, secretKey, projectID, region, endpoint)
	if err != nil {
		return fmt.Errorf("create client: %w", err)
	}

	poolIDs, err := parseIDs(requiredEnv("POOL_RESOURCE_IDS"), 1)
	if err != nil {
		return fmt.Errorf("pool IDs: %w", err)
	}
	if os.Getenv("AUDIT_MODE") == "verify" {
		if err := verifyExactParentSet(ctx, client, poolIDs); err != nil {
			return err
		}
		fmt.Printf("VERIFY_EXACT_PARENT_SET_PASS count=%d\n", len(poolIDs))
		return nil
	}

	deleteIDs, err := parseIDs(requiredEnv("DELETE_RESOURCE_IDS"), 2)
	if err != nil {
		return fmt.Errorf("delete IDs: %w", err)
	}
	if len(deleteIDs) != 2 {
		return fmt.Errorf("expected exactly two delete IDs, got %d", len(deleteIDs))
	}
	poolSet := idSet(poolIDs)
	for _, id := range deleteIDs {
		if _, ok := poolSet[id]; !ok {
			return fmt.Errorf("delete ID %s is not in the declared pool", id)
		}
	}

	anchor, err := client.GetSubNetworkInterface(ctx, deleteIDs[0])
	if err != nil {
		return fmt.Errorf("get anchor %s: %w", deleteIDs[0], err)
	}
	if err := verifyExactParentSet(ctx, client, poolIDs); err != nil {
		return fmt.Errorf("baseline parent set: %w", err)
	}
	for _, id := range deleteIDs[1:] {
		item, err := client.GetSubNetworkInterface(ctx, id)
		if err != nil {
			return fmt.Errorf("get delete candidate %s: %w", id, err)
		}
		if item.ParentID != anchor.ParentID || item.SubnetID != anchor.SubnetID {
			return fmt.Errorf("delete candidates do not share parent/subnet")
		}
	}

	for _, id := range deleteIDs {
		if err := client.DeleteSubNetworkInterface(ctx, id); err != nil {
			return fmt.Errorf("delete existing free SubENI %s: %w", id, err)
		}
		if err := waitNotFound(ctx, client, id); err != nil {
			return err
		}
	}
	fmt.Printf("DELETE_EXISTING_PASS count=%d\n", len(deleteIDs))

	request := hwAPI.CreateSubENIRequest{
		TrunkInterfaceID: anchor.ParentID,
		SubnetID:         anchor.SubnetID,
		SecurityGroupIDs: append([]string(nil), anchor.SecurityGroups...),
		Tags:             map[string]string{"cilium-audit": "audit81", "crud-mode": "single"},
	}
	rawClient, err := buildRawVPCClient(accessKey, secretKey, projectID, region, endpoint)
	if err != nil {
		return err
	}

	created := make([]string, 0, 2)
	defer func() {
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cleanupCancel()
		for _, id := range created {
			_ = client.DeleteSubNetworkInterface(cleanupCtx, id)
		}
	}()

	id, single, err := client.CreateSubNetworkInterface(ctx, request)
	if err != nil {
		return fmt.Errorf("single create: %w", err)
	}
	created = append(created, id)
	if err := validateCreated(single, id, anchor); err != nil {
		return fmt.Errorf("single create response: %w", err)
	}
	if err := verifyTags(rawClient, id, request.Tags); err != nil {
		return fmt.Errorf("verify single inline tags: %w", err)
	}
	shown, err := client.GetSubNetworkInterface(ctx, id)
	if err != nil {
		return fmt.Errorf("show single %s: %w", id, err)
	}
	if err := validateCreated(shown, id, anchor); err != nil {
		return fmt.Errorf("show single response: %w", err)
	}
	listed, err := client.ListSubNetworkInterfaces(ctx, anchor.ParentID)
	if err != nil {
		return fmt.Errorf("list after single create: %w", err)
	}
	if !containsID(listed, id) {
		return fmt.Errorf("single-created SubENI %s missing from list", id)
	}
	fmt.Println("SINGLE_CREATE_GET_LIST_INLINE_TAG_PASS")
	if err := client.DeleteSubNetworkInterface(ctx, id); err != nil {
		return fmt.Errorf("delete single %s: %w", id, err)
	}
	if err := waitNotFound(ctx, client, id); err != nil {
		return err
	}
	created = created[:0]
	fmt.Println("SINGLE_CREATE_GET_LIST_TAG_DELETE_PASS")

	request.Tags["crud-mode"] = "batch"
	batch, err := client.BatchCreateSubNetworkInterfaces(ctx, 2, request)
	if err != nil {
		return fmt.Errorf("batch create: %w", err)
	}
	if len(batch) != 2 {
		return fmt.Errorf("batch returned %d resources", len(batch))
	}
	for _, item := range batch {
		if item == nil || item.ID == "" {
			return fmt.Errorf("batch returned an item without an ID")
		}
		created = append(created, item.ID)
	}
	for _, item := range batch {
		if err := validateCreated(item, item.ID, anchor); err != nil {
			return fmt.Errorf("batch create response: %w", err)
		}
		if err := verifyTags(rawClient, item.ID, request.Tags); err != nil {
			return fmt.Errorf("verify batch inline tags: %w", err)
		}
		shown, err := client.GetSubNetworkInterface(ctx, item.ID)
		if err != nil {
			return fmt.Errorf("show batch item %s: %w", item.ID, err)
		}
		if err := validateCreated(shown, item.ID, anchor); err != nil {
			return fmt.Errorf("show batch response: %w", err)
		}
	}
	listed, err = client.ListSubNetworkInterfaces(ctx, anchor.ParentID)
	if err != nil {
		return fmt.Errorf("list after batch create: %w", err)
	}
	for _, id := range created {
		if !containsID(listed, id) {
			return fmt.Errorf("batch-created SubENI %s missing from list", id)
		}
	}
	for _, id := range append([]string(nil), created...) {
		if err := client.DeleteSubNetworkInterface(ctx, id); err != nil {
			return fmt.Errorf("delete batch item %s: %w", id, err)
		}
		if err := waitNotFound(ctx, client, id); err != nil {
			return err
		}
	}
	created = created[:0]
	fmt.Println("BATCH_CREATE_GET_LIST_TAG_DELETE_PASS count=2")

	remaining := make([]string, 0, len(poolIDs)-len(deleteIDs))
	deletedSet := idSet(deleteIDs)
	for _, id := range poolIDs {
		if _, deleted := deletedSet[id]; !deleted {
			remaining = append(remaining, id)
		}
	}
	if err := verifyExactParentSet(ctx, client, remaining); err != nil {
		return fmt.Errorf("post-cleanup parent set: %w", err)
	}
	fmt.Printf("HUAWEICLOUD_CLOUD_CRUD_PASS baseline=%d remaining=%d\n", len(poolIDs), len(remaining))
	return nil
}

func buildRawVPCClient(accessKey, secretKey, projectID, region, endpoint string) (*hwVPC.VpcClient, error) {
	credentials, err := auth.NewBasicCredentialsBuilder().WithAk(accessKey).WithSk(secretKey).WithProjectId(projectID).SafeBuild()
	if err != nil {
		return nil, fmt.Errorf("build raw verification credentials: %w", err)
	}
	builder := hwVPC.VpcClientBuilder().WithCredential(credentials).
		WithHttpConfig(config.DefaultHttpConfig().WithTimeout(10 * time.Second))
	if strings.TrimSpace(endpoint) != "" {
		builder = builder.WithEndpoint(endpoint)
	} else {
		vpcRegion, regionErr := hwVPCRegion.SafeValueOf(region)
		if regionErr != nil {
			vpcRegion = coreregion.NewRegion(region, fmt.Sprintf("https://vpc.%s.myhuaweicloud.com", region))
		}
		builder = builder.WithRegion(vpcRegion)
	}
	httpClient, err := builder.SafeBuild()
	if err != nil {
		return nil, fmt.Errorf("build raw verification VPC client: %w", err)
	}
	return hwVPC.NewVpcClient(httpClient), nil
}

func verifyTags(client *hwVPC.VpcClient, id string, expected map[string]string) error {
	response, err := client.ShowSubNetworkInterface(&vpcmodel.ShowSubNetworkInterfaceRequest{SubNetworkInterfaceId: id})
	if err != nil {
		return err
	}
	if response.SubNetworkInterface == nil {
		return fmt.Errorf("empty tag verification response")
	}
	actual := make(map[string]string, len(response.SubNetworkInterface.Tags))
	for _, tag := range response.SubNetworkInterface.Tags {
		actual[tag.Key] = tag.Value
	}
	if len(actual) != len(expected) {
		return fmt.Errorf("tag count mismatch: got %d want %d", len(actual), len(expected))
	}
	for key, value := range expected {
		if actual[key] != value {
			return fmt.Errorf("tag %q mismatch", key)
		}
	}
	return nil
}

func requiredEnv(name string) string {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		fmt.Fprintf(os.Stderr, "required environment variable %s is empty\n", name)
		os.Exit(2)
	}
	return value
}

func parseIDs(raw string, minimum int) ([]string, error) {
	parts := strings.Split(raw, ",")
	result := make([]string, 0, len(parts))
	seen := map[string]struct{}{}
	for _, part := range parts {
		id := strings.TrimSpace(part)
		if id == "" {
			return nil, fmt.Errorf("empty resource ID")
		}
		if _, ok := seen[id]; ok {
			return nil, fmt.Errorf("duplicate resource ID %s", id)
		}
		seen[id] = struct{}{}
		result = append(result, id)
	}
	if len(result) < minimum {
		return nil, fmt.Errorf("need at least %d resource IDs", minimum)
	}
	return result, nil
}

func verifyExactParentSet(ctx context.Context, client *hwAPI.Client, expectedIDs []string) error {
	if len(expectedIDs) == 0 {
		return fmt.Errorf("expected resource set is empty")
	}
	anchor, err := client.GetSubNetworkInterface(ctx, expectedIDs[0])
	if err != nil {
		return fmt.Errorf("get verification anchor %s: %w", expectedIDs[0], err)
	}
	items, err := client.ListSubNetworkInterfaces(ctx, anchor.ParentID)
	if err != nil {
		return fmt.Errorf("list parent %s: %w", anchor.ParentID, err)
	}
	actual := make([]string, 0, len(items))
	for _, item := range items {
		actual = append(actual, item.ID)
	}
	expected := append([]string(nil), expectedIDs...)
	sort.Strings(actual)
	sort.Strings(expected)
	if strings.Join(actual, ",") != strings.Join(expected, ",") {
		return fmt.Errorf("parent resource set mismatch: expected=%d actual=%d", len(expected), len(actual))
	}
	return nil
}

func validateCreated(item *eniTypes.SubENI, id string, anchor *eniTypes.SubENI) error {
	if item == nil {
		return fmt.Errorf("nil SubENI")
	}
	if item.ID != id || item.ID == "" || item.PrivateIPAddress == "" {
		return fmt.Errorf("invalid identity or address")
	}
	if item.ParentID != anchor.ParentID || item.SubnetID != anchor.SubnetID {
		return fmt.Errorf("unexpected parent or subnet")
	}
	return nil
}

func containsID(items []*eniTypes.SubENI, id string) bool {
	for _, item := range items {
		if item != nil && item.ID == id {
			return true
		}
	}
	return false
}

func waitNotFound(ctx context.Context, client *hwAPI.Client, id string) error {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		_, err := client.GetSubNetworkInterface(ctx, id)
		if errors.Is(err, hwAPI.ErrNotFound) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("verify deletion of %s: %w", id, err)
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("wait for deletion of %s: %w", id, ctx.Err())
		case <-ticker.C:
		}
	}
}

func idSet(ids []string) map[string]struct{} {
	result := make(map[string]struct{}, len(ids))
	for _, id := range ids {
		result[id] = struct{}{}
	}
	return result
}
