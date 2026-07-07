# HuaweiCloud Runtime Checklist

Use this checklist after applying the patch series and deploying the customized
Cilium build with `ipam.mode=huaweicloud`.

- Confirm the HuaweiCloud operator starts as `cilium-operator-huaweicloud`.
- Confirm `CiliumNode.spec.huawei-cloud` contains instance, VPC, zone, trunk
  interface, subnet, and security group data.
- Confirm SubENI allocation updates `CiliumNode.status.huawei-cloud`.
- Confirm Pod allocation returns gateway, CIDR, VLAN ID, and MAC data.
- Confirm `cilium_hwc_srcip4` and `cilium_hwc_vlan_mac` receive entries for
  new Pods.
- Confirm Pod traffic reaches the Kubernetes API Server.
- Confirm ClusterIP service access works from HuaweiCloud allocated Pods.
- Confirm DNS resolution works from HuaweiCloud allocated Pods.
- Confirm cross-node Pod traffic works.
- Confirm deleting a Pod removes related BPF map entries.
