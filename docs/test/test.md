# p4

## 组件

![image](file://D:/ucloud/BGW/%EF%BB%BFBGW/p4.png?lastModify=1604919760)

|              |                                                              |
| ------------ | ------------------------------------------------------------ |
| **pipeline** | 一台P4设备可根据配置信息划分为两个Pipeline，每个 pipeline 可以理解为一台虚拟的 P4 设备 ，每个pipeline绑定的面板口，在ONL系统中创建对应的虚拟接口（802.1Q封装），虚拟接口通过归属于不同的VRF实现两个pipeline之间的ONL层三层隔离。 |
| **bfswitch** | 与管理平台对接, 主要用于上下线 P4 设备. 例如 P4 设备配置/获取Port、Pipeline、Online、BGP, VRF等配置信息 |
| **bf-sde**   | 提供了 grpc 接口给控制台调用实现读写流表操作、统计信息       |
| **gobgp**    | 配置信息来源于bfswitch，与物理网络构建 BGP邻居, 将 VIPs 宣告出去 |

![img](https://cdn.nlark.com/yuque/0/2020/png/1744928/1594813825456-f1c08609-f050-4a7e-a07f-e0112222508a.png)



## 处理流程

![image-20200703103026919.png](https://cdn.nlark.com/yuque/0/2020/png/1744928/1594807009958-648ba4b1-ad6e-4235-af19-7d91e7f546e3.png?x-oss-process=image%2Fresize%2Cw_746)

# BGW

主要用于解决VPC3.0首包时延问题。

## 功能

### 支持报文类型

* IP版本
  * underlay支持IPV4
  * overlay支持IPV4
* 封装
  * GRETAP
  * VXLAN
  * GRETAP与VXLAN互转
* 支持报文大于MTU时回ICMP报文，用于虚机间协商MTU
* TTL小于2，BGW回ICMP报文，用于虚机trace route
* 不支持报文重组

### Meter

​	支持下发flow总数据包限速

### 数据面处理

#### 同VPC - 同子网

![image.png](https://cdn.nlark.com/yuque/0/2020/png/1744928/1594982620236-adf6109b-ecce-4142-b827-174a5791013e.png?x-oss-process=image%2Fresize%2Cw_414)

* 源VM发出ARP查询报文，OVS发现本地没有转发至CGW
* CGW按照分片规则发送给指定的BGW分片
* BGW进行ARP代答并生成flow data报文返回源宿主机，OVS通过learn生成流表
* 后续IPV4报文命中流表，直接发送至对端VM

#### 同VPC - 跨子网

![image.png](https://cdn.nlark.com/yuque/0/2020/png/1744928/1594982659611-7710436d-53c8-46fc-8fda-4945ab4a4604.png)

* 源VM发出IPV4报文，OVS发现本地没有转发至CGW
* CGW按照分片规则发送给指定的BGW分片
* BGW转发IPV4报文并生成flow data报文返回源宿主机，OVS通过learn生成流表
* 后续IPV4报文命中流表，直接发送至对端VM

#### 跨项目

![image](file://D:/ucloud/BGW/%EF%BB%BFBGW/%E8%B7%A8%E9%A1%B9%E7%9B%AE.png?lastModify=1605001147)

* 源VM发出ARP/IPV4报文, OVS发现本地没有转发至CGW
* CGW按照分片规则发送给指定的BGW分片
* BGW发现为跨项目互通, 按照跨项目打通关系复制对应份的报文修改VNI并将源信息填至overlay across vni header 中发送至CGW
* CGW按照分片原则发送给指定的BGW分片
* BGW收到不需要处理的报文则丢弃
* BGW收到需要助理的报文后则提取overlay across vni header 中的源信息并进行ARP代答或IPV4报文转发；同时生成flow data报文发送至源宿主机，OVS通过learn生成流表
* 后续报文命中流表，直接发送至对端VM

### 周边服务

1. bgwmgr： 部署在kun上，每个pod对应一台P4， 故不支持扩缩容。主要功能为： 通过resource-service获取VPC控制面数据下发给P4
2. bgw-checktool : 部署在kun上，每个pod对应一个set，需要与物理网络打通，不支持扩缩容。主要功能为：验证bgw device  forward是否正常；p4设备表项查询。
3. bgw-fwdcheck： 部署在kun上，每个pod对应一个set，需要与物理网络打通，不支持扩缩容。主要功能为： 从resource service获取数据，构造remote_mirror报文发给bgw，接收报文后检查报文是否符合预期。
4. bgw-dbcheck：部署在kun上，每个pod对应一台P4，不支持扩容。主要功能为： 从resource service获取数据，与bgw转发面表项对账

## 部署


结合CGW的部署图如下
	![广州h02](C:\Users\luke\Desktop\广州h02.png)

1. bgw按SET进行水平扩容
2. 每个SET在不同AZ内最少有一台虚拟bgw设备，即一个pipeline，未分配的pipeline用于后续灰度
3. 每个虚拟bgw设备均与物理网络建立BGP，且每个SET下的所有虚拟bgw均宣告相同的BGP地址
4. 物理网络保证就近接入

### 上线

1. 安装ONL, 参见https://ushare.ucloudadmin.com/pages/viewpage.action?pageId=31077704中的第5、6步
2. 安装bf-sde以及bfswitch（bfswitch有默认的pipeline）
3. 根据物理连线情况调用bfswitch的SetPorts、SetHostInterfaces、SetBGPConfig、SetBGPNetworks和SetVRFs接口设置端口、BGP以及VRF信息。其中VRF用于隔离pipeline、BGP用于与物理网络建立BGP并宣告VIP、端口用于设置端口速率等。
4. 调用bfswitch的SetOnlineInfos对该设备进行上线
5. 通过ping测试BGP连通性以及有效性。若BGP地址ping不通可ssh上机器通过gobgp相关命令查询bgp邻居状态或抓包进行排查
6. 调用bfswitch的SetPipeline接口设置pipeline后调用ReStart重启bfswitch（pipeline的p4name不能与上一个版本相同）
7. 调用bfswitch的SetConfig接口设置bfswitch的配置，若不调用则使用bfswitch的默认配置
8. 有以下几种上线情况
   - 地域上线BGW集群步骤如下：
     - 上线bgwmgr、bgw-dbcheck和bgw-fwdcheck
     - 调用cgw-service的AllocateVips为bgw集群申请一个或多个VIP
     - 调用bfswitch的SetBGPNetworks设置BGP地址(物理网络提供)
     - 调用bfswitch的SetOnlineInfos将bgw设备上线
     - 通过ping测试BGP连通性以及有效性。若BGP地址ping不通可ssh上机器通过gobgp相关命令查询bgp邻居状态或抓包进行排查
     - 调用CreateRedirectCluster创建bgw集群
     - 若创建集群时未填写分片规则或灰度规则可调用AddShardingRule和AddCanaryRule进行配置
     - 按照分片规则为每个VM调用bgw-checktool验证bgw转发行为
     - 业务将路由指向从cgw-service申请出的VIP
   - 上线BGW-SET步骤如下：
     - 上线bgwmgr、bgw-dbcheck和bgw-fwdcheck
     - 调用cgw-service的AllocateVips为bgw集群申请一个或多个VIP
     - 调用bfswitch的SetBGPNetworks设置BGP地址(物理网络提供)
     - 调用bfswitch的SetOnlineInfos将BGW设备上线
     - 通过ping测试BGP连通性以及有效性。若BGP地址ping不通可ssh上机器通过gobgp相关命令查询bgp邻居状态或抓包进行排查
     - 调用UpdateRedirectCluster为BGW集群添加一个subset ip(物理网络提供给BGW的IP)
     - 调用AddCanaryRule以VM为粒度灰度到新的BGW-SET(每灰度一个VM需要调用bgw-checktool验证BGW转发行为;CGW可支持先按明细值灰度, 最大256条; 再按/24位掩码聚合, 最后512条规则, 可支持128K台VM;灰度完一个VNI下的所有VM后先为该VNI配置分片规则再将其灰度规则删除)
   - 上线BGW设备步骤如下：
     - 上线bgwmgr、bgw-dbcheck
     - 调用bfswitch的SetBGPNetworks设置BGP地址(物理网路提供, 每个BGW-SET下的BGW设备的BGP地址相同)
     - 调用bfswitch的SetOnlineInfos将BGW设备上线
     - 通过ping测试BGP连通性以及有效性。若BGP地址ping不通可ssh上机器通过gobgp相关命令查询bgp邻居状态或抓包进行排查

### 下线

1. 下线一台BGW设备：下线对应的bgw-dbcheck、bgwmgr;调用bfswitch的SetOnlineInfos接口对该设备进行下线，待BGP状态切换成非Established时即下线成功
2. 下线BGW-SET：通过灰度规则/分片规则将流量移到其他的BGW-SET;下线对应的bgw-dbcheck、bgwmgr、bgw-fwdcheck;调用cgw-service的UpdateRedirectCluster删除该BGW-SET;调用bfswitch的SetOnlineInfos对设备进行下线，待BGP状态切换成非Established时即下线成功
3. 下线整个地域的BGW：将业务移走;调用cgw-service相关接口删除对应RedirectCluster并调用ReleaseVIP释放宣告在cgw上的VIP;调用bfswitch的SetOnlineInfos对设备进行下线，待BGP状态切换成非Established时即下线成功

### 灰度

如下图所示每个AZ最少留一个pipeline用于bgw灰度
![image](D:/ucloud/BGW/﻿BGW/灰度.png)

1. 上线新bgw分片设备、待VIP（图中的192.168.0.4）宣告成功后进行下一步操作
2. 上线bgwmgr
3. 上线bgw-dbcheck
4. 上线bgw-fwdcheck
5. 调用cgw-service的UpdateRedirectCluster新增一个subset（图中的192.168.0.4）
6. 先按照VM粒度灰度到新的BGW集群（每次灰度均需要调用cgw-checktool来验证是否转发至新的BGW分片，同时调用bgw-checktool来验证BGW流量是否转发正常），后聚合成一个子网。依次类推，直到需要灰度的分片所有流量均灰度到新bgw分片时可进行bgw分片下线操作后下线的bgw分片作为新的分片用于灰度
7. 每个操作均需要观察bgw-dbcheck以及bgw-fwdcheck是否有新告警

