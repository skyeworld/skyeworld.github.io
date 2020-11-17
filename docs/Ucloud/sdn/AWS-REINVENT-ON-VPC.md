# AWS re:Invent VPC相关分享

<p align="right"><font color=Grey>try.chen 2020-11-08</font></p>

主要介绍了VPC以及相关实现，介绍了Mapping-Service，提出宿主机节点cache miss后不会走slow path（不会query Mapping-Service）：

[AWS re:Invent 2015 | (NET403) Another Day, Another Billion Packets - YouTube](https://www.youtube.com/watch?v=3qln2u1Vr2E)

再次简单介绍了VPC Mapping-Service（策略有push/pre-loading/cache等），hyperplane（以及hyperplane的shuffle shading机制）、privatelink

[AWS re:Invent 2017: Another Day, Another Billion Flows (NET405) - YouTube](https://www.youtube.com/watch?v=8gc2DgBqo9U)

![](media/aws-1.png)

![](media/aws-2.png)

![](media/aws-3.png)

> 更多关于hyperplane的介绍可以参考：[AWS Hyperplane浅谈](https://zhuanlan.zhihu.com/p/188735635).
