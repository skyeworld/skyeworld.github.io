# VPC3.0系列（九）：BGW和动态学习

<p align="right"><font color=Grey>try.chen 2020-07-02</font></p>

> 在前面的设计中，我们的目标是致力于通过无状态和水平扩容来解决性能问题，但是随着业务的发展，当我们遇到超大规模VPC（30w~60w vm）推送时面临的性能问题该如何解决？如何平衡这其中的成本、收益和风险？

作为先行者，Google已经公布了他们在超大规模VPC推送、函数计算/Serverless场景中的实践，以及遇到的瓶颈。随着网络规模的提升，推送的时间越来越不可控，呈现线性上涨的趋势。为此，Google设计了`Hoverboard`模型，借鉴了传统网络中的协议更新理念，做到快速更新。

<img src="media/vpc3-9-2.png" title="" alt="" data-align="center">

可以看到有了Hoverboard模型之后，网络的推送速度提升了37倍，除此之外整体的推送效率也得到了提升：

![](media/vpc3-9-3.png)

Google给出的经验是，83%的pair从未有过通信，98%的pair流量小于20kbps，当把阈值设到50kbps时，Hoverboard模型只需要下发全量推送模型的**0.1%**！

基于Google的成功经验，我们设计和开发了BGW架构，BGW相对于Hoverboard的区别主要在于BGW是”来者不拒“，而Hoverboard是基于阈值的offload，目前这一套方案仍然是业界领先的设计。

<img src="media/vpc3-8-1.png" title="" alt="" data-align="center">

对于BGW和VPC3.0的整体交互流程主要如下：

- 控制面将变更推送给BGW；

- 宿主机ovs上发生flow miss之后，默认转发给BGW；

- BGW进行目的转发，转发的同时，按照DCP协议构造UDP报文，该报文中包含需要学习的关键信息，将其发送给源宿主机；

- 源宿主机上DPEcho监听在该DCP协议规定的UDP端口收包，收包之后根据报文内容生成flow，并下发到ovs，完成offload；

- 后续报文可以直接通过ovs flow进行转发，而无需上送到BGW；
