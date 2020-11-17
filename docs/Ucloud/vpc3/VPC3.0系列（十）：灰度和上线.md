# VPC3.0系列（十）：灰度和上线

<p align="right"><font color=Grey>try.chen 2020-10-21</font></p>

> 为了学习UXR*零case上线*的过程，VPC3.0对上线和灰度做了很多考虑。

## 灰度流程

VPC3完整灰度流程如下图：

![](media/vpc3-grey.jpg)

### 灰度流程中的安全事项

#### 一、VPC2 fallback

VPC3在pipeline设计中，对于数据表查找miss的流量不会直接进行丢弃，而是返回table0中继续按照VPC2的逻辑进行转发，以此避免灰度和上线过程中由于VPC3下发异常带来的连通性中断风险，通过fallback进入VPC2处理。

同时为了避免BB探测流量也被fallback到VPC2，导致灰度验证不准确，因此对于BB染色流量将不会进入fallback，以此准确验证VPC3灰度过程中的连通性。

#### 二、旁路验证

通过第二次BB发出染色探测报文，使得实际还未灰度时探测报文即可进入VPC3灰度，并通过进入VPC3 Pipline flow来提前验证VPC3的flow完整性、正确性和连通性。

此外通过三次BB的成功率比较和包量比较，确认VPC3灰度前后连通性不受影响。

#### 三、ToS染色的不稳定性

取决于协议栈实现，不同协议栈或应用程序对于SYN报文中的ToS可能并不会继承，因此回包SYN ACK或RST中是否协议BB染色的ToS可能是不确定的。

针对这种情况，我们设计了如下思路来解决：

**1、Learn-Flow**

通过入向的SYN报文来学习进行反向染色的flow，主动将VM发出的tcp(11,11)的流量进行ToS染色，但该方案在具体实现时有一点难度。

```
# match中必须要设置nw_tos=0x0，否则会造成循环，先去tos-learn(table=123)表设置tos，设置好再回来
cookie=0x96,table=1,priority=48000,tcp,metadata=0x1,nw_tos=0x0,tp_src=11,tp_dst=11 actions=resubmit(,123),resubmit(,1)

# tos=40
cookie=0x97,table=1,priority=45150,tcp,metadata=0x1,nw_tos=40,tp_src=11,tp_dst=11 actions=move:NXM_OF_IN_PORT[]->NXM_NX_REG14[0..15],move:NXM_NX_TUN_ID[0..31]->NXM_NX_REG15[],set_field:0x8100->tun_id,set_field:0.0.0.0->tun_src,load:0->NXM_OF_IN_PORT[],set_field:172.31.169.218->tun_dst,output:64200,learn(cookie=0x98,idle_timeout=3,table=123,priority=1000,NXM_OF_IN_PORT[],dl_type=0x0800,ip_proto=6,tp_src=11,tp_dst=11,load:40->NXM_OF_IP_TOS[]),move:NXM_NX_REG14[0..15]->NXM_OF_IN_PORT[],move:NXM_NX_REG15[]->NXM_NX_TUN_ID[0..31],set_field:0->metadata,resubmit(,10)

# 学习的flow示例：
cookie=0x98, duration=1.039s, table=123, n_packets=0, n_bytes=0, idle_timeout=3, priority=1000,tcp,in_port=0,tp_src=11,tp_dst=11 actions=load:0x28->NXM_OF_IP_TOS[]
```

**2、动态下发**

类似于快杰的动态下发，在BB进行tos染色探测时，动态下发上文中的学习flow，进行反向ToS染色。

#### 四、VPC2活跃校验

在地域级VPC3灰度和上线完成后，需要验证通过vpc2 fallback下发的flow理论上应该为0，因此需要通过River来确认VPC2活跃flow应该为0（或仅有VPC3不支持的场景，如公共服务等）。

---

其他参考文档：

[Ushare-VPC3.0升级](https://ushare.ucloudadmin.com/pages/viewpage.action?pageId=28403953)
