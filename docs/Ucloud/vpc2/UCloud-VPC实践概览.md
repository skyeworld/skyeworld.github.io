# UCloud VPC实践概览

<p align="right"><font color=Grey>try.chen 2019-04-01</font></p>

## SDN 网络编程模型

> 按照 Google Andromeda 对 SDN 网络的编程模型定义，可以划分为如下三种：
> 
> - Preprogrammed Model
> 
> - On Demand Model
> 
> - Gateway Model

其中，三种模型都有各自的特点：

| 模型                   | 特点                  | 优点           | 缺点                                                          |
|:-------------------- | ------------------- | ------------ | ----------------------------------------------------------- |
| Pre programmed Model | 预先下发 full-mesh 规则   | 一致性、性能可预测性   | 控制面复杂度是网络规模的 O(n2)，任何网络变化都需要传递至所有节点                         |
| On Demand Model      | 网络流的第一个包被送至控制面下发规则。 | 比第一种拥有更好的扩展性 | 1.  首包拥有非常高的时延；<br/>2.  对控制面负载状态很敏感；<br/>3. 控制面会受到 DDoS 攻击； |
| Gateway Model        | VM 把所有流量都送到中心化网关处理  | 性能可预测性、扩展性   | 网络流量的均值和峰值差距非常大（可能超过 100 倍），导致网关模式的利用率很低、TCO很高              |

基于此，Google 公开了其仙女座虚拟网络控制平面使用的模型: **Hoverboard Model**

UCloud VPC 控制平面的演进思路即从 On Demand 过渡到 Hoverboard Model。

### VPC 1.0：经典大二层架构

关键词：linux bridge / iptables / ebtables

### VPC 2.0：被动下发模型

#### 虚拟网络架构

计算节点上装有 ovs（openvswtich）， 负责overlay 网络的转发、封装和解封装。

![ovs](media/ovs.png)

vm 通过 tap 口和 ovs bridge 互联。bridge 收到来自 vm 的包后，首先查看本地是否有对应该流的flow，若有则按照 flow 转发。

![flow](media/flow.png)

flow 根据业务类型，可能包含二层、三层、四层等信息。

如果未匹配到任何 flow，则会通过默认 flow ，产生 OpenFlow Packet-In 事件并送往 OpenFlow 控制器。

![vpc2](media/vpc3.png)

> 控制器会根据 DB 中的数据计算出相应flow，并通过 RPC 回复给 Agent，Agent 通过 OpenFlow 协议与 ovs 交互，下发 flow。

对于路由，通过 RouteController 进行管理，通过 pull、push 两条路径向计算节点推送其上 VM 关心的路由 flow。

![vpcrt](media/vpc2-rt2.png)

被动下发模型拥有如下几个优点：

- 原理简单，复杂度低；

- 控制面可水平扩展；

但同时被动下发模型也遇到了很多问题：

- OpenFlow 模型非常学术化和理论化，转发面通过向控制面要数据，会导致转发面的请求和控制面**耦合**在一起，而转发面的规模和控制面不在同一量级，这也就导致了如下几点；

- 

- **控制面 DDoS**，由于转发面流量被耦合到控制面，导致控制面始终深受 ARP扫描、DDoS **攻击**影响（只要用户向其合法地址空间发送报文，flow miss 后就会送上控制面），进而转嫁到数据库。虽然通过限速、恶意流量识别、封禁等手段环节，但其中的平衡很难调整；

因此，在这些问题的背景下，推动flow 下发模型演进到第三代（类似 Google Hoverboard）。

#### 异构网络

![vpc2-eg](media/vpc2-eg2.png)

异构网络之间，通过各自的 GW 作为网关介入 VPC 公有网络，因此 VPC 需要知晓异构网络之间的全部细节。这会带来如下问题：

- 公有云新上特性时，需要全部关联产品 GW 都支持，如公有云支持 VIP 后，HGW、CGW 都需要支持，耦合严重，开发迭代困难；

- 异构网络需要彼此交换路由细节，复杂度提升；

因此对于异构网络，推动演进到集中式交换网关。

#### 架构能力

- 高可用能力
  
  - Controller 集群主主部署，分可用区部署，通过 zookeeper 提供服务发现、上线下线能力；
  
  - GW 通过 BGP ECMP + VIP 提供高可用能力；

- 灰度能力
  
  - PacketIn 通过 Proxy 按照用户灰度；
  
  - 路由推送不支持按照用户粒度灰度；
  
  - API 通过 API-GW 灰度；

### VPC3.0 主动推送模型

#### 虚拟网络架构

> 通过借鉴 Google 的设计理念，实现 VPC 内 推送full-mesh flow，并将flow miss 流量送至中心化网关。中心化网关拥有 Region 内全部信息，因此可以正确转发。同时，中心化网关通过监控 top pps/bps流， 通知控制面下发 offload 规则，将大流量卸载至计算节点上。

甚至计算节点上，初始状态下完全不推送任何 flow，默认送给 中心化 GW，完全通过中心化 GW 将超过指定阈值的流量 offload 回 CN 节点。

最终达到 Google 论文中给定的状态：计算节点上只需下发 20%的 flow，即可 offload 80%的流量，最终 GW 上只保留长尾流量。

---

![hb-3](media/hb-3.png)

---

![hb-4](media/hb-4.png)

---

![hb-5](media/hb-5.png)

---

![hb-1](media/hb-1.png)

---

![hb-2](media/hb-2.png)

#### 控制面

![](media/15510108769872/15510142300704.jpg)

**设计思想**

- 控制面微服务化
  
  - 不同对象由不同微服务 Service 管理，Service 之间互相解耦，通过 gRPC互相调用。以此支持 Service 之间的独立演进，支持快速迭代，Service 之间支持完善的灰度能力；
  
  - 北向 FE 向外提供 HTTP API，对内通过调用微服务 Service 间的 gRPC 完成网络对象的 CRUD 和编排，以此实现用户请求到网络对象的转换、RPC 的转换、事务的控制、资源和订单计费的处理，内部 Service 只需要关心对象；
  
  - 微服务间通过 ServiceMesh 完成服务治理、流量控制、灰度发布；
  
  - 微服务化改造的目的：
    
    - 降低单个模块的复杂度，便于开发和上线；
    
    - 提供完善的模块间调用的灰度能力，便于灰度验证；
    
    - 将网络能力服务化，避免不同系统中的重复实现；

- 基于事件和版本号的更新
  
  - Service 在更新对象后，通过 EventService产生全局版本号和 scope 版本号，并发布对象变更事件到 MQ 中；
  
  - FlowManager 订阅对象MQ，当发现对象变更事件后，通过内置的 ObjectFlowInterpreter，实现 Object -> OpenFlow 的转换。将该 flow 集合打上版本号、对象 ID 后，更新到 Cache（Redis） 中。并产生 Flow 变更事件，发布到 Flow 变化 MQ 中（topic 为 VPC）；
  
  - DPAgent 向 MQ 订阅事件，topic 为 nc 所关心的 VPC。当订阅到 Flow 变更事件后，FlowAgent 拉取到远端版本号。若远端version 大于本地 version，则根据对象 ID 进行批量更新；
  
  - DPAgent 本地内存 cache 通过 ovslib 事件与 ovs userspace flow 保持一致；
  
  - DPAgent 通过 ovslib 事件发现 vport 的变更状态，并向上游同步；

- 水平扩展和 AutoScale
  
  - FlowManager 南北向按照用户UID 进行分片，支持水平扩展，解决性能问题
  
  - Service 部署在 K8S 集群上，按照 work load 进行 scale up/ scale down；

- 缓存
  
  - FlowManager 会将构件好的 Flow 缓存进redis，并保存版本和对象 ID 信息；
  
  - DPAgent 内存 cache 中会保存两份 cache：本地 actual flow cache，以及远端 expect cache，两份 cache 都基于事件增量构建；

- 基于 ServiceMesh灰度能力（详细见下文）

##### 推送流程

**Manager**

<img title="" src="media/15510108769872/FlowManager-workflow.jpg" alt="loading-ag-1598" data-align="center">

**Agent**

<img src="media/15510108769872/DPAgent-workflow.jpg" title="" alt="工作流程" data-align="center">

#### 转发面

> 计算节点上 OVS 的 flow 设计借鉴了 SDN 转发与控制分离的思想，将 flow 分为逻辑 flow 和数据 flow。逻辑 flow 定义 pipeline 和行为，数据 flow 将 match-action 抽象为函数，提供 input，输出 output。

##### 入向处理流程

<img src="media/15510108769872/inbound-pipeline.png" title="" alt="inbound" data-align="center">

##### 出向处理流程

![outbound](media/15510108769872/outbound-pipeline.png)

![pipeline](media/15510108769872/pipeline.png)

> 通过将 metadata 作为状态机 ID，实现 flow 中的状态跳转，实现伪状态机机制。

##### 转发表

![forward](media/15510108769872/forward-pipeline.png)

##### 数据表

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

通过 v3 Flow 设计达到如下目标：

- flow 逻辑与数据分离；逻辑 flow 即为VPC特性、测试用例，数据 flow 即为对象、数据库；便于回归测试、全量对账和校验；

- 数据 flow 不含任何逻辑，可被不同逻辑复用，节约表项规则；

- 参考 iptables 设计，多级分表、预留诸多 hook点；借鉴 service-chain 的理念，通过 pipeline 表将各逻辑表串联在一起。方便集成新业务、新场景以及灰度切换等；

> 后续发展目标：
> 
> 外网 NAT 、外网防火墙、外网限速下沉到计算节点，内网支持限速、QoS 等。

#### 基于 ServiceMesh 的灰度发布

![service-mesh-1](media/service-mesh-1.jpg)

#### 

![service-mesh-2](media/service-mesh-2.png)

#### 

- 服务治理
  
  - 基于 etcd + pilot / k8s + istio 的服务发现，通过 service-name 进行寻址；
  
  - 通过发布系统(K8S)进行服务的部署和上下线，并自动更新到 envoy；
  
  - service配置文件维护在 etcd 中，支持版本回滚；

- 流量管理
  
  - 丰富的流量管理策略；
  
  - 支持熔断、重试、超时、限流等等；

- 路由策略（灰度）
  
  - 通过在 gRPC metadata(http2.0 header) 中带入指定的灰度信息，支持细粒度的灰度能力；
  
  - 支持细至某个 Service 中某个函数的灰度（http2.0 uri)；
  
  - 支持将请求灰度至指定版本、集群、或者任何自定义 label ；

- ingress gateway
  
  - gateway 模式的 envoy 同时作为入口网关，并通过 grpc-gateway 实现 gRPC 和 HTTP 请求的互相转换，之后通过 envoy gateway 提供 api 层的灰度策略和路由能力；

![](media/15510108769872/15510667174103.jpg)

#### 可靠性机制

- 高可用能力
  
  - envoy 通过 BGP ECMP VIP 接入，提供负载均衡及就近接入；
  
  - service、manager 支持无损升级；
  
  - 基于 ServiceMesh 的服务发现和切换能力；
  
  - 基于 sentinel-redis 的 redis 高可用能力；
  
  - 基于 K8S 的动态伸缩容扩展能力；

- 验证机制
  
  - 结构化 flow 对账，内嵌于 DPAgent 中，与上游 FlowManager 进行周期性版本号对账；
  
  - Redis 对账，内嵌于 FlowManager 中，保证 redis 中缓存的全量数据与上游微服务始终保持一致；
  
  - 发布、变更验证
    
    - 支持分布式全量连通性验证，DPAgent 通过构造ICMP 报文并注入 OVS 以此模拟用户指定源目的访问，监控并上报连通性、时延（黑盒）；
    
    - 支持活跃 Flow 验证，从活跃分析系统取出某用户最近 7 天内活跃的流，并构建通信源目，使用上述第三部方式，进行全量验证（黑盒）；
    
    - 控制面特性回归验证，基于逻辑 flow 提炼出的BDD 风格测试用例，用于测试特性是否满足需求；

- 灰度能力
  
  - 控制面细粒度的灰度能力：支持 VM、子网、VPC、项目、公司、客户等级、权重等多种粒度灰度能力；
  
  - 转发面通过 pipieline 支持将制定 VM（用户）切入单独 pipeline 进行转发面灰度；

![inspect-1](media/inspect-1.png)

#### 异构网络

![xr-1](media/xr-1.png)

通过中心化网关 UXR 提供异构网络之间的解耦，不同 GW 会向 UXR 发送路由，而 UXR 会收全网路由。当网络域需要与异构网络通信时，发送给 UXR 即可，UXR 会正确的路由到对端。

因此，通过 UXR 提供了如下好处：

- 异构网络解耦，无相互依赖，独立演进，适合新特性的发布和迭代；

- 不同域之间不再需要交换路由细节，降低单个网络的复杂度，并减少相互相应，提高稳定性；

- UXR 可提供一致性 hash 功能，支持下游如 ULB 等有状态业务；

> UXR 使用 barefoot 可编程交换芯片和 P4 语言进行开发，并使用 P4Runtime 作为管理平面。单机提供 6.4T 的线速转发能力。目前 P4 提供了诸如 UXR、NAT64、CGW（一致性网关）等特性。

## 总结

- 控制面微服务化，按照对象拆分微服务，独自迭代发布；

- 控制面Service交付基于 Docker，通过 K8S 提供控制面的快速、自动的扩缩容能力；

- 基于服务网格建设流量管理、灰度发布、trace 和监控；

- flow 下发模型基于 hoverboard 理念，通过 hoverboard 降低推送规模和复杂度，并通过反馈机制将大流量bypass hoverboard，只保留长尾流量；

- 推送机制通过事件、版本号、对象 ID 来保证一致性、及时性、增量等；

- 通过内存 cache、redis 缓存热点数据（包括全量数据），提升性能；

- 通过中心化网关解耦异构网络，作为 Router 完成路由的交互和报文的转发，降低整网复杂度；

- 中心化网关逐渐采用 P4 替代 DPDK；

### 全量下发

> 1. 针对全量下发问题，Controller 可以根据事件增量的构建本地全量数据，并通过共享存储（redis cluster）共享给controller集群；
> 
> 2. 分布式更新 redis 时，按照 UID 或者 VPC 粒度进行加锁；
> 
> 3. 各 Controller 可按照分片，独自构建全量数据的不同集合或者分片，可水平扩展并提高稳定性；
> 
> 4. 只有当新一轮全量构建构建完成时，才会原子替换 redis 中的已有全量数据；
> 
> 5. 通过 Controller 分片，水平扩展构建速率和性能；

**优点：**

1. 全量数据下发不依赖于的及时构建；极端情况下，异常、重启、掉电时，控制面可快速下发全量数据；

2. 全量下发时间从 全量构建+网络 RPC缩短为网络 RPC；

3. 控制面对全量数据做缓存，实现全量拉取请求的折叠，降低 load 和后端 DB 的压力；

4. 控制面可按照分片，分片构建并写入 redis，响应全量下发请求时，从 redis 读取所有数据并返回；以此可水平扩展构建性能；

**缺点：**

1. 引入 cache，增加复杂度，需要保证 cache与 DB 的一致性；
