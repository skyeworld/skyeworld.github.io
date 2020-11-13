# FlowV3设计

<p align="right"><font color=Grey>try.chen 2019-04-29</font></p>

## 流程

**出入向判断：**

![](media/15510108769872/flow-bound.jpg)

**入向flow pipeline：**

![](media/15510108769872/inbound-pipeline.png)

**出向flow pipeline:**

![](media/15510108769872/outbound-pipeline.png)

**pipeline原理：**

![](media/15510108769872/pipeline.png)

**forward-pipeline原理：**

![](media/15510108769872/forward-pipeline.png)

其中，约定通过forward表后，应维持以下全局寄存器：

| 寄存器  | 含义               | 备注                               |
| ---- | ---------------- | -------------------------------- |
| reg5 | 封装类型             | 0: GRE, 1: VXLAN, 2:GROUP, 3:不封装 |
| reg6 | value, 视reg5含义不同 | port或者groupId                    |

## 数据表

定义如下数据表：

| 功能             | 表项  |
| -------------- | --- |
| MAC查询VNI       | 200 |
| MAC查询IPv4      | 201 |
| MAC查询IPv6      | 202 |
| IPv4查询MAC      | 203 |
| IPv6查询MAC      | 204 |
| MAC查询DPID/PORT | 205 |
| DPID查询Datapath | 206 |
| IPv4路由表查询      | 207 |
| IPv6路由表查询      | 208 |
| VIP表           | 209 |
| QoS表           | 210 |
| 灰度表            | 211 |
| 出入向判断表         | 212 |
| 广播集群表          | 213 |
| Meter表         | 214 |
| 查询是否去往本地       | 215 |
| 查询UXR          | 216 |

目前现网已使用如下table：0, 1, 100, 101, 110, 111, 115, 120。

---

**Table 200：MAC查询VNI**

输入：

- xreg0 MAC

输出：

- reg0 表示是否找到，1表示找到，0表示未找到
- reg1 VNI

```bash
cookie=0xInterfacePrefixMac, table=200, priority=30000, xreg0=0x525400445566 actions=load:0x1->reg0,load:0x562->reg1
cookie=0xPipelinePrefix, table=200, priority=1 actions=load:0x0->reg0
```

---

**Table 201：MAC查询IPv4**

输入：

- reg0 VNI
- xreg1 MAC

输出：

- reg0 表示是否找到，1表示找到，0表示未找到
- reg1 IPv4（Primary）

作用：此表用于支持DHCP。

```bash
cookie=0xInterfacePrefixMac, table=201, priority=30000, reg0=0x562, xreg1=0x525400112233 actions=load:0x1->reg0, load:0xac1f932c->reg1
cookie=0xInterfacePrefixMac, table=201, priority=1 actions=load:0x0->reg0
```

---

**Table 202：MAC查询IPv6：**

输入：

- reg0 VNI
- xreg1 MAC

输出：

- reg0 表示是否找到，1表示找到，0表示未找到
- xxreg1 IPv6（Primary）

作用：此表用于支持DHCPv6。

```bash
cookie=0xInterfacePrefixMac, table=201, priority=30000, reg0=0x562, xreg1=0x525400112233 actions=load:0x1->reg0, load:0xIPv6->xxreg1
cookie=0xInterfacePrefixMac, table=201, priority=1 actions=load:0x0->reg0
```

---

**Table 203：IPv4查询MAC**

**输入：**

- reg0 VNI
- reg1 IPv4

**输出：**

- reg0 表示是否找到，1表示找到，0表示未找到
- xreg1 MAC

作用：此表用于ARP。

```bash
cookie=0xInterfacePrefixMac,table=203,priority=30000,reg0=vni2,reg1=ip2 actions=load:0x1->reg0,load:0xMAC2->xreg1
cookie=0xInterfacePrefixMac,table=203,priority=1 actions=load:0x0->reg0
```

---

**Table 204：IPv6查询MAC**

输入：

- reg0 VNI
- xxreg1 IPv6

输出：

- reg0 表示是否找到，1表示找到，0表示未找到
- xreg1 MAC

作用：此表用于IPv6 Neighbor Discovery。

```bash
cookie=0xInterfacePrefixMac,table=204,priority=30000,reg0=vni2,xxreg1=ipv6 actions=load:0x1->reg0,load:0xMAC->xreg1
cookie=0xInterfacePrefixMac,table=204,priority=1 actions=load:0x0->reg0
```

---

**Table 205：MAC查询DPID和Port**

输入：

- reg0 VNI
- xreg1 MAC

输出：

- reg0 标识是否找到，1标识找到，0标识未找到
- reg1 port
- reg2 dpid

```bash
cookie=0xInterfacePrefixMac, table=205, priority=30000,reg0=0x562,xreg1=0x525400112233 actions=load:0x1->reg0,0x33->reg1,0x203040->reg2
cookie=0xPipelinePrefix, table=205, priority=1 actions=load:0x0->reg0,exit
```

---

**Table 206：DPID查询Datapath**

输入：

- xreg0 dpid

输出：

- reg0 表示是否找到, 1表示找到,0表示未找到
- reg1 封装目的地址
- reg2 封装类型(0表示GRE, 1表示VXLAN)
- reg3 标识是否是本地(无需封装)，1标识是，0标识否

```bash
# dst is local
cookie=0xDpidPrefix, table=206, priority=40000,xreg0=dpid_local actions=load:1->reg0,load:1->reg3

cookie=0xDpidPrefix, table=206, priority=30000,xreg0=0x525400112233 actions=load:0x1->reg0,load:0xac17283f->reg1,load:0->reg2,load:0->reg3

cookie=0xDpidPrefix, table=206, priority=1 actions=load:0x0->reg0,exit
```

---

**Table 207：查询IPv4路由表**

输入：

- reg0 VNI
- reg1 目的IP
- reg2 源IP
- xreg2 源mac（用于支持origin_addr）

输出：

- reg0 表示是否找到，1表示找到，0表示未找到
- reg1 新的tun_id
- reg2 nexthop 类型，0标识datapath，1标识local，2标识drop，3标识unsupport
- reg3 nexthop_id(dpid)
- xreg3 新的dl_dst
- xreg4 新的dl_src

```bash
# 子网路由表
cookie=0xRoutePrefixSubRT, table=207, priority=30016, reg0=0x562, reg1=10.18.0.0/16, reg2=0xac78b2c3 actions=load:0x1->reg0, load:0x652->reg1, load:0x291832->reg2, load:525400112233->xreg3, load:0xfaffffffffff->xreg4
# 指定dl_src（origin_addr）
cookie=0xRoutePrefixSubRT, table=207, priority=30016, reg0=0x562, reg1=10.172.0.0/16, reg2=0xac78b2c3, xreg2=0x525400112233 actions=load:0x1->reg0, load:0x652->reg1, load:0x291832->reg2, load:525400112233->xreg3, load:0xfaffffffffff->xreg4

# vpc路由表，支持丢弃
cookie=0xRoutePrefixVPCRT, table=207, priority=30016,reg0=0x562, reg1=10.172.0.0/16, reg2=0xac78b2c3 actions=load:0x1->reg0,load:0x2->reg2

# region路由表，无需vni，本地共用
cookie=0xRoutePrefixRegionRT, table=207, priority=30016,reg1=100.64.0.0/18, reg2=0xac78b2c3 actions=load:0x1->reg0, load:0x652->reg1, load:0x291832->reg2, load:525400112233->xreg3, load:0xfaffffffffff->xreg4

cookie=0xRoutePrefix, table=207, priority=1 actions=load:0x0->reg0
```

---

**查询IPv6路由表**

输入（寄存器不够）：

- reg0 VNI
- xxreg1 目的IP
- xxreg2 源IP

输出：

- reg0 表示是否找到，1表示找到，0表示未找到
- reg1 新的tun_id
- reg2 nexthop 类型，0标识datapath，1标识local，2标识drop，3标识unsupport
- reg3 nexthop类型
- xreg3 新的dl_dst
- xreg4 新的dl_src

```bash
# 子网路由表
cookie=0xRoutePrefixSubRT, table=208, priority=30016, reg0=0x562,xxreg1=2000:1000:3000::/48,xx reg2=2000:2000:3000::123/128 actions=load:0x1->reg0, load:0x652->reg1, load:0x291832->reg2, load:525400112233->xreg3, load:0xfaffffffffff->xreg4

# vpc路由表，丢弃
cookie=0xRoutePrefixVPCRT, table=208, priority=30016,reg0=0x562,,xxreg1=2000:1000:3000::/48 actions=drop

# region路由表，无需vni，本地共用
cookie=0xRoutePrefixRegionRT, table=208, priority=30016,xxreg1=2000:1000:3000::/48, xxreg2=2000:1000:3000::123/128 actions=load:0x1->reg0, load:0x652->reg1, load:0x291832->reg2, load:525400112233->xreg3, load:0xfaffffffffff->xreg4

cookie=0xRoutePrefix, table=208, priority=1 actions=load:0x0->reg0,exit
```

---

**Table 209：查询VIP**

输入：

- reg0 UNI
- reg1 IPv4
- reg2 IPv4 (由于garp和ovs的限制，需要同时传入spa/tpa)

输出：

- reg0 表示是否找到，1表示找到，0表示未找到
- reg1 1表示是VIP，0表示不是VIP

```bash
cookie=0xInterfacePrefixIP, table=209,priority=30000,reg0=vni2,reg1=vip2,reg2=vip2 actions=load:0x1->reg0
cookie=0xInterfacePrefixIP, table=209, priority=1 actions=load:0x0->reg0
```

---

**Table 210 QoS表**

> 只有出向需要过QoS表，选择对应的qos等级，并通过等级对应到相应的output port，入向不需要。

输入：

- reg0 vni

输出：

- reg0 标识QoS级别，对应1~4，默认为0

```bash
cookie=0xQoSPrefix, table=210, priority=30000,reg0=0x562 actions=load:0x1->reg0
cookie=0xQoSPrefix, table=210, priority=30000,reg0=0x563 actions=load:0x2->reg0
cookie=0xQoSPrefix, table=210, priority=30000,reg0=0x564 actions=load:0x3->reg0
cookie=0xQoSPrefix, table=210, priority=30000,reg0=0x565 actions=load:0x4->reg0
cookie=0xQoSPrefix, table=210, priority=1 actions=oad:0x0->reg0
```

---

**Table 211：查询灰度表**

**输入：**

- xreg0 MAC

**输出：**

- reg0 1标识灰度，0标识未灰度

```bash
cookie=0xInterfacePrefixMac, table=211, priority=30000,xreg0=0x525400112233 actions=load:0x1->reg0

cookie=0xInterfacePrefixMac, table=211, priority=30000,xreg0=0x525400445566 actions=load:0x1->reg0
cookie=0xPipelinePrefix, table=211, priority=1 actions=load:0x0->reg0
```

---

**Table 212：出入向判断表**

**输入：**

- reg0 in_port
- reg1 tunnel_id

**输出：**

- reg0 表示方向，1标识出向，0标识入向

```bash
# nvgre
cookie=0xPipelinePrefix, table=212, priority=30000,reg0=64200 actions=load:0x0->reg0
# vxlan
cookie=0xPipelinePrefix, table=212, priority=30000,reg0=64300 actions=load:0x0->reg0
cookie=0xPipelinePrefix, table=212, priority=29000,reg1=0 actions=load:0x1->reg0
cookie=0xPipelinePrefix, table=212, priority=28000 actions=load:0x0->reg0
```

---

**Table 213：查询广播集群DPID**

**输出：**

- reg0 表示是否查到，1标识查到，0标识未查到
- xreg1 广播集群dpid

```bash
cookie=0xBroadcastGW,table=213,priority=30000 actions=load:0x1->reg0, load:dpid1->xreg1
```

---

**Table 214：Meter表**

**输入：**

- xreg0 mac

**输出：**

- reg0 标识是否查到，1标识查到，0标识未查到
- reg1 标识queue_id

```bash
cookie=0xMeterPrefixMac, table=214, priority=30000,xreg0=0x525400112233 actions=load:0x1->reg0,load:0x20->reg1
cookie=0xMeterPrefixMac, table=214, priority=1 actions=load:0x0->reg0
```

---

**Table 215：查询是否去往本地**

**输入：**

- xreg0 dst_dpid

**输出：**

- reg0 标识是否是本地DPID，1标识是，0标识不是

```bash
cookie=0xDpidPrefix, table=215, priority=30000, xreg0=dpid_xxx actions=load:0x1->reg0
cookie=0xDpidPrefix, table=215, priority=1 actions=load:0x0->reg0
```

作用：该表用于同宿主机转发、forward等情况。
---

**Table 216：查询UXR**

**输出：**

- xreg0 uxr dpid

```bash
cookie=0xUXRPrefix,table=216,priority=30000 actions=load:0x1->reg0, load:dpid1->xreg1
```

## 逻辑表

### 出入向pipeline

**table 0**

```bash
# 已存在
cookie=0x20003, table=0, priority=62000,metadata=0 actions=set_field:0x1->metadata,resubmit(,1)
```

**table 1**

```bash
# 1. 首先进行出入向判断
cookie=0xPipelinePrefix, table=1, priority=40000,metadata=0x1 actions=set_field:0x0->metadata,move:in_port->reg0,move:tunnel_id->reg1,resubmit(,212),set_field:0x20->metadata,resubmit(,1)

# 2. 区分出入向，并判断是否进入VPC3.0灰度
# 入向
cookie=0xPipelinePrefix, table=1, priority=40000,metadata=0x20,reg0=0 actions=set_field:0x0->metadata,move:dl_dst->xreg0,resubmit(,211),set_field:0x30->metadata,resubmit(,1)
# 出向
cookie=0xPipelinePrefix, table=1, priority=40000,metadata=0x20,reg0=1 actions=set_field:0x0->metadata,move:dl_src->xreg0,resubmit(,211),set_field:0x40->metadata,resubmit(,1)

# 3. 灰度控制
# 入向，进入灰度
cookie=0xPipelinePrefix, table=1, priority=40000,metadata=0x30,reg0=1 actions=set_field:0x0->metadata,resubmit(,2)
# 入向，未进入灰度，保持原有逻辑
cookie=0xPipelinePrefix, table=1, priority=40000,metadata=0x30,reg0=0 actions=set_field:0x100->metadata,resubmit(,1)

# 出向，进入灰度
cookie=0xPipelinePrefix, table=1, priority=40000,metadata=0x40,reg0=1 actions=set_field:0x0->metadata,resubmit(,20)
# 出向，未进入灰度，保持原有逻辑
cookie=0xPipelinePrefix, table=1, priority=40000,metadata=0x40,reg0=0 actions=set_field:0x100->metadata,resubmit(,1)

# ACL 出入向Flow（兼容存量）
# 现网中以下三条acl flow match中metadata=0x1，需要修改为0x100
# 切换时，可以保持0x1和0x100同时存在。
cookie=0x20007, table=1, priority=30001,tun_id=0,metadata=0x100 actions=resubmit(,111),resubmit(,115)
cookie=0x20007, table=1, priority=30000,metadata=0x100 actions=resubmit(,110),resubmit(,115)
cookie=0x20004, table=1, priority=0,metadata=0x100 actions=set_field:0x2->metadata,resubmit(,0)
```

**table 2 入向pipeline**

```bash
# 通过metadata作为状态机ID，依次resubmit到相应的表中执行
# 跳转到入向hook表
cookie=0xPipelinePrefix, table=2, priority=30000,metadata=0x0 actions=set_field:0x0->metadata,resubmit(,3),set_field:0x10->metadata,resubmit(,2)

# 跳转到入向转发前hook表
cookie=0xPipelinePrefix, table=2, priority=30000,metadata=0x10 actions=set_field:0x0->metadata,resubmit(,4),set_field:0x20->metadata,resubmit(,2)
# 跳转到转发表
cookie=0xPipelinePrefix, table=2, priority=30000,metadata=0x20 actions=set_field:0x0->metadata,resubmit(,40),set_field:0x30->metadata,resubmit(,2)
# 跳转到入向转发后hook表
cookie=0xPipelinePrefix, table=2, priority=30000,metadata=0x30 actions=set_field:0x0->metadata,resubmit(,5),set_field:0x40->metadata,resubmit(,2)
# 跳转到入向ACL表
cookie=0xPipelinePrefix, table=2, priority=30000,metadata=0x40 actions=set_field:0x0->metadata,resubmit(,6),set_field:0x50->metadata,resubmit(,2)
# 跳转到入向安全组
cookie=0xPipelinePrefix, table=2, priority=30000,metadata=0x50 actions=set_field:0x0->metadata,resubmit(,7),set_field:0x60->metadata,resubmit(,2)
# 跳转到入向output前hook表
cookie=0xPipelinePrefix, table=2, priority=30000,metadata=0x60 actions=set_field:0x0->metadata,resubmit(,8),set_field:0x70->metadata,resubmit(,2)
# 跳转到output表
cookie=0xPipelinePrefix, table=2, priority=30000,metadata=0x70 actions=set_field:0x0->metadata,resubmit(,9),set_field:0x80->metadata,resubmit(,2)
```

**table 3 入向hook表**

```bash
# 默认为空
```

**table 4 入向转发前hook表**

```bash
# 默认为空
```

**table 5 入向转发后hook表**

```bash
# 默认为空
```

**table 6 入向ACL表**

```bash
# 需要把存量acl的flow下发到此表中
```

**table 7 入向安全组表**

```bash
# 默认为空
```

**table 8 入向output前hook表**

```bash
# 默认为空
```

**table 9 入向output表**

```bash
cookie=0xPipelinePrefix, table=9, metadata=0x0,priority=30000 actions=output:reg6
```

**table 20 出向pipeline**

```bash
# 通过metadata作为状态机ID，依次resubmit到相应的表中执行
# 跳转到出向hook表
cookie=0xPipelinePrefix, table=20, priority=30000,metadata=0x0 actions=set_field:0x0->metadata,resubmit(,21),set_field:0x10->metadata,resubmit(,20)
# 跳转到mac/port校验表
cookie=0xPipelinePrefix, table=20, priority=30000,metadata=0x10 actions=set_field:0x0->metadata,resubmit(,22),set_field:0x20->metadata,resubmit(,20)
# 跳转到mac信息查询（源vni）
cookie=0xPipelinePrefix, table=20, priority=30000,metadata=0x20 actions=set_field:0x0->metadata,resubmit(,23),set_field:0x30->metadata,resubmit(,20)
# 跳转到出向安全组
cookie=0xPipelinePrefix, table=20, priority=30000,metadata=0x30 actions=set_field:0x0->metadata,resubmit(,24),set_field:0x40->metadata,resubmit(,20)
# 跳转到出向ACL
cookie=0xPipelinePrefix, table=20, priority=30000,metadata=0x40 actions=set_field:0x0->metadata,resubmit(,25),set_field:0x50->metadata,resubmit(,20)
# 跳转到出向转发前hook表
cookie=0xPipelinePrefix, table=20, priority=30000,metadata=0x50 actions=set_field:0x0->metadata,resubmit(,26),set_field:0x60->metadata,resubmit(,20)
# 跳转到转发表
cookie=0xPipelinePrefix, table=20, priority=30000,metadata=0x60 actions=set_field:0x0->metadata,resubmit(,40),set_field:0x70->metadata,resubmit(,20)
# 跳转到出向转发后hook表
cookie=0xPipelinePrefix, table=20, priority=30000,metadata=0x70 actions=set_field:0x0->metadata,resubmit(,27),set_field:0x80->metadata,resubmit(,20)
# 跳转到QoS表
cookie=0xPipelinePrefix, table=20, priority=30000,metadata=0x80 actions=set_field:0x0->metadata,resubmit(,28),set_field:0x90->metadata,resubmit(,20)
# 跳转到限速表
cookie=0xPipelinePrefix, table=20, priority=30000,metadata=0x90 actions=set_field:0x0->metadata,resubmit(,29),set_field:0x100->metadata,resubmit(,20)
# 跳转到出向output前hook表
cookie=0xPipelinePrefix, table=20, priority=30000,metadata=0x100 actions=set_field:0x0->metadata,resubmit(,30),set_field:0x110->metadata,resubmit(,20)
# 跳转到output表
cookie=0xPipelinePrefix, table=20, priority=30000,metadata=0x110 actions=set_field:0x0->metadata,resubmit(,55),set_field:0x120->metadata,resubmit(,20)
```

**table 21 出向hook表**

```bash
# 默认为空
```

**table 22 mac/port校验**

```bash
cookie=0xPipelinePrefix, table=22, priority=30000 actions=move:in_port->reg0, move:dl_src->xreg1,resubmit(,215),set_field:0x10->metadata,resubmit(,22)
# mac/port校验不通过
cookie=0xPipelinePrefix, table=22, priority=29000,metadata=0x10,reg0=0 actions=exit
```

**table 23 mac信息查询**

```bash
cookie=0xPipelinePrefix, table=22, priority=30000 actions=move:dl_src->xreg0,resubmit(,200),set_field:0x10->metadata,resubmit(,22)
# 未查询到mac信息（需要考虑特殊情况：fa:ff:ff:ff:ff:ff/fc:ff:ff:ff:ff:ff(cnat2)等）
cookie=0xPipelinePrefix, table=22, priority=29000,metadata=0x10,reg0=0 actions=exit
# 查询到mac信息（vni），放入reg4中，后续匹配时可以直接使用

cookie=0xPipelinePrefix, table=22, priority=29000,metadata=0x10,reg0=1 actions=move:reg1->reg4
```

**table 24 出向安全组**

```bash
# 默认为空
```

**table 25 出向ACL**

```bash
# 默认为空
```

**table 26 出向转发前hook表**

```bash
# 默认为空
```

**table 27 出向转发后hook表**

```bash
# 默认为空
```

**table 28 QoS表**

```bash
# 首先判断是否需要过qos port，否则不做任何操作
cookie=0xPipelinePrefix, table=28, priority=40000,metadata=0x0, reg5=0x2 actions=note:0x1
cookie=0xPipelinePrefix, table=28, priority=40000,metadata=0x0, reg5=0x3 actions=note:0x1

# 首先查询qos等级
cookie=0xPipelinePrefix, table=28, priority=30000,metadata=0x0 actions=set_field:0x0->metadata,move:reg4->reg0,resubmit(,210),set_field:0x10->metadata,resubmit(,28)

# qos等级查找port
cookie=0xPipelinePrefix, table=28, priority=30000,metadata=0x10 actions=set_field:0x0->metadata,move:reg5->reg1,resubmit(,31),set_field:0x20->metadata,resubmit(,28)

# 保存QoS port到全局寄存器中
cookie=0xPipelinePrefix, table=28,priority=30000,metadata=0x20 actions=move:reg0->reg6
```

**table 29 限速表**

```bash
# 默认为空
```

**table 30 出向output前hook表**

```bash
# 默认为空
```

**table 31 QoS Port映射表**

```bash
# 输入
# reg0: qos class
# reg1: overlay encap type(0: gre, 1: vxlan)
# 输出
# reg0: qos port

# gre
cookie=0xQoSPrefix, table=xxx, priority=30000, reg0=0x0, reg1=0 actions=load:64200->reg0
cookie=0xQoSPrefix, table=xxx, priority=30000, reg0=0x1, reg1=1 actions=load:64201->reg0
cookie=0xQoSPrefix, table=xxx, priority=30000, reg0=0x2, reg1=2 actions=load:64202->reg0
cookie=0xQoSPrefix, table=xxx, priority=30000, reg0=0x3, reg1=3 actions=load:64203->reg0
cookie=0xQoSPrefix, table=xxx, priority=30000, reg0=0x4, reg1=4 actions=load:64204->reg0

# vxlan
cookie=0xQoSPrefix, table=xxx, priority=30000, reg0=0x1, reg1=0 actions=load:64300->reg0
cookie=0xQoSPrefix, table=xxx, priority=30000, reg0=0x1, reg1=1 actions=load:64301->reg0
cookie=0xQoSPrefix, table=xxx, priority=30000, reg0=0x2, reg1=2 actions=load:64302->reg0
cookie=0xQoSPrefix, table=xxx, priority=30000, reg0=0x3, reg1=3 actions=load:64303->reg0
cookie=0xQoSPrefix, table=xxx, priority=30000, reg0=0x4, reg1=4 actions=load:64304->reg0
```

### 转发表（forward）

**table 40 forward dispatch表**

```bash
# controller-alive探测报文
cookie=0xPipelinePrefix, table=40, priority=43000,in_port=65200 actions=CONTROLLER(ryu)

# traceroute with QoS
cookie=0xPipelinePrefix, table=40, priority=42000,ip,ip_dscp=32,nw_ttl=1 actions=CONTROLLER(ryu)

# arp，跳转到arp处理表
cookie=0xPipelinePrefix, table=40, priority=41000,arp actions=resubmit(,41)

# ipv6, neighbor discovery
cookie=0xPipelinePrefix, table=40, priority=41000,icmp6,icmpv6_type=135,icmpv6_code=0 actions=resubmit(,41)

# dhcp
cookie=0xPipelinePrefix, table=40, priority=41000,udp,dl_dst=ff:ff:ff:ff:ff:ff,tp_src=68,tp_dst=67 actions=CONTROLLER(dpagent)

# dhcpv6
cookie=0xPipelinePrefix, table=40, priority=41000,udp,dl_dst=ff:ff:ff:ff:ff:ff,tp_src=546,tp_dst=547 actions=CONTROLLER(dpagent)

# 三层转发
cookie=0xPipelinePrefix, table=40, priority=40000,ip,dl_dst=fa:ff:ff:ff:ff:ff actions=resubmit(,61)
cookie=0xPipelinePrefix, table=40, priority=40000,ipv6,dl_dst=fa:ff:ff:ff:ff:ff actions=resubmit(,61)

# 广播
cookie=0xPipelinePrefix, table=40, priority=40000,ip,dl_dst=ff:ff:ff:ff:ff:ff actions=resubmit(,54)
cookie=0xPipelinePrefix, table=40, priority=40000,ipv6,dl_dst=ff:ff:ff:ff:ff:ff actions=resubmit(,54)

# 二层转发
cookie=0xPipelinePrefix, table=40, priority=20000,ip actions=resubmit(,60),
cookie=0xPipelinePrefix, table=40, priority=20000,ipv6 actions=resubmit(,60)
```

**table 60 二层转发**

```bash
cookie=0xPipelinePrefix, table=60, priority=20000 actions=resubmit(,50),resubmit(,42),resubmit(,52)
```

**table 61 三层转发**

```bash
cookie=0xPipelinePrefix, table=61, priority=20000 actions=resubmit(,51),resubmit(43),resubmit(,53)
```

**table 50 二层转发 prehook**

```bash
# 默认为空
```

**table 42 二层转发**

```bash
cookie=0xPipelinePrefix, table=42, metadata=0x0,priority=30000 actions=move:reg4->reg0, move:dl_dst->xreg1, resubmit(,205),move:reg1->reg7,reg2->xreg0,resubmit(,206),set_field:0x10->metdata,resubmit(,42)

# 远程，保存封装类型到reg6，保存port到reg7（前序flow）
cookie=0xPipelinePrefix, table=42, metadata=0x10,priority=40000,reg3=0 actions=move:reg3->reg6

# 本地，置位不封装到reg6，保存port到reg7（前序flow）
cookie=0xPipelinePrefix, table=42, metadata=0x10,priority=40000,reg3=1 actions=load:3->reg6
```

**table 52 二层转发 post hook**

```bash
# 默认为空
```

**table 55 封装**

```bash
# ip
cookie=0xPipelinePrefix, table=55, priority=30000,metadata=0x0 actions=output:reg6
```

**table 56 广播转发**

```bash
cookie=0xPipelinePrefix, table=56, priority=40000 actions=resubmit(,213),move:xreg1->xreg0,resubmit(,206),resubmit(,55)
```

**table 51 三层转发 pre hook**

```bash
# 默认为空
```

**table 43 三层转发（路由查找）**

```bash
# ipv4

# 首先进行路由查找
cookie=0xPipelinePrefix, table=43, priority=40000,metadata=0x0 actions=move:reg4->reg0,move:nw_dst->reg1,move:nw_src->reg2,move:dl_src->xreg2,set_field:0x0->metadata,resubmit(,207),set_field:0x10->metadata,resubmit(,43)

# 解析nexthop类型
# drop
cookie=0xPipelinePrefix, table=43, priority=40000,metadata=0x10, reg2=0x2 actions=drop,exit

# unsupport goto uxr
cookie=0xPipelinePrefix, table=43, priority=40000,metadata=0x10, reg2=0x3 actions=resubmit(,216),move:xreg1->xreg0,resubmit(,206),resubmit(,55)

# local, 替换目的mac，然后走二层转发，最后替换源mac
cookie=0xPipelinePrefix, table=43, priority=40000,metadata=0x10, reg2=0x1 actions=move:xreg3->dl_dst,resubmit(,50),move:xreg4->dl_src

# datapath
cookie=0xPipelinePrefix, table=43, priority=40000,metadata=0x10, reg2=0x0 actions=move:xreg3->dl_dst,move:xreg4->dl_src,move:reg3->reg7,set_field:0x20->metadata,resubmit(,43)

# 再进行dpid查找
cookie=0xPipelinePrefix, table=43, priority=40000,metadata=0x20 actions=set_field:0x0->metadata,move:reg7->xreg0,resubmit(,206),set_field:0x30->metadata,resubmit(,43)

# 远程，保存封装类型到reg6，保存port到reg7(gre)
cookie=0xPipelinePrefix, table=43, metadata=0x30,priority=40000, reg0=1, reg3=0, reg2=0 actions=move:reg3->reg5,load:64200->reg6

# 远程，保存封装类型到reg6，保存port到reg7(vxlan)
cookie=0xPipelinePrefix, table=43, metadata=0x30,priority=40000, reg0=0, reg3=0, reg2=1 actions=move:reg3->reg5,load:64300->reg6

# 本地，替换目的mac，然后走二层转发，然后替换源mac
cookie=0xPipelinePrefix, table=43, metadata=0x20,priority=40000, reg0=1, reg3=1 actions=move:xreg3->dl_dst,resubmit(,50),move:xreg4->dl_src
```

**table 53 三层转发 post hook**

```bash
# 默认为空
```

**table 57 dhcp/dhcpv6**

```bash
# dhcp，送到controller处理
cookie=0xPipelinePrefix, table=57, priority=40000 actions=CONTROLLER
```

### ARP

ARP处理逻辑如下：

![](media/15510108769872/arp-workflow.png)

**table 41 arp表**

```bash
# 先判断是否是vip garp
# ipv4
cookie=0xPipelinePrefix,table=41,metadata=0x0,priority=40000,arp,dl_dst=ff:ff:ff:ff:ff:ff actions=move:arp_spa->reg0, move:arp_tpa->reg1, resubmit(,209), set_field:0x1->metadata,resubmit(, 41)
# ipv6，需要细化，此处暂时没有仔细研究
cookie=0xPipelinePrefix,table=41,metadata=0x0,priority=40000,dl_dst=ff:ff:ff:ff:ff:ff,icmp6,icmpv6_type=135,icmpv6_code=0 actions=move:nd_target->reg0, move:nd_target->reg1, resubmit(,209),set_field:0x1->metadata,resubmit(, 41)

# 是vip garp，送往广播集群
cookie=0xPipelinePrefix,table=41,metadata=0x1,priority=40000,reg0=1 actions=resubmit(,54)

# 不是vip garp，走代答逻辑
cookie=0xPipelinePrefix,table=41,metadata=0x1,priority=40000,reg0=0 actions=set_field:0x2->metadata,resubmit(,41)

# 代答arp
cookie=0xPipelinePrefix,table=41,metadata=0x2,arp,dl_dst=ff:ff:ff:ff:ff:ff actions=move:reg4->reg0, move:arp_tpa->reg1,resubmit(,203),move:eth_src->eth_dst,move:xreg1->eth_src,set_field:2->arp_op,move:reg0->arp_spa,move:NXM_OF_ARP_SPA[]->NXM_OF_ARP_TPA[],move:arp_sha->arp_tha,move:xreg1->arp_sha,IN_PORT
# 代答ipv6 neighbor discovery，查询204表

# 单播arp
cookie=0xPipelinePrefix,table=41,metadata=0x2,arp actions=resubmit(,50),resubmit(,42),resubmit(,52),resubmit(,55)
cookie=0xPipelinePrefix,table=41,metadata=0x2,icmp6,icmpv6_type=135,icmpv6_code=0 actions=resubmit(,50),resubmit(,42),resubmit(,52),resubmit(,55)
```
