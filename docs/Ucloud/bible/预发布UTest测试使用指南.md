# 预发布UTest使用指南

<p align="right"><font color=Grey>try.chen 2020-11-05</font></p>

> 预发布02使用前需要找@try.chen创建子账号。

UTest使用链接：[https://ut.ucloudadmin.com](https://ut.ucloudadmin.com/#/auto/dashboard)

## 添加账户

首次使用需要添加账号信息：新建账号

![](media/utest-1.png)

![](media/utest-2.png)

环境信息如下（示例）：

| 账号名称   | 账号邮箱               | 环境URL                               | 公钥  | 私钥  |
| ------ | ------------------ | ----------------------------------- | --- | --- |
| pre    | try.chen@ucloud.cn | https://api.pre.ucloudadmin.com     | --  | --  |
| pre02  | try.chen@ucloud.cn | http://api-pre2.pre.ucloudadmin.com | --  | --  |
| online | try.chen@ucloud.cn | https://api.ucloud.cn               | --  | --  |

> Q: 如何获取公钥和私钥？
> A: 控制台右侧点击账户详情-->**API密钥**
> ![](media/utest-8.png)

## 执行测试

以VPC测试为例，选择《子网测试用例》并点击执行：

![](media/utest-3.png)

> 工作台中选好测试用例之后，也可以点击右上角的**切换视图**按钮到编辑界面，并可以按照需求增删、修改测试用例之后再点击执行。

![](media/utest-4.png) 

填写环境、属性等值之后（以上字段解释在文末），即可点击确认执行，进入测试结果页面。

| 属性                  | 含义                                                                                                               | 推荐值             |
| ------------------- | ---------------------------------------------------------------------------------------------------------------- | --------------- |
| ucloud_access       | 连接vm/sandbox的途径，可选private/internet，应总是填写private                                                                  | private         |
| ucloud_sandbox_mode | 是否采用沙盒模式测试，若为true将创建namespace替代真实云主机。沙盒模式只针对白名单用户开放。目前沙盒模式只支持PRE02和华南。                                           | true<br/>（虚拟网络） |
| ucloud_is_fail_stop | 测试用例失败时是否保留环境和资源，默认false即不保留。如果需要排查测试用例失败原因则填写true，并事后需要手动清理资源。                                                  | false           |
| ucloud_uhost_ip_set | 对于sandbox模式，一般对应不同测试环境，如VPC2/VPC3，对于真实云主机则可以指定SET和宿主机创建。格式一般为 ip:setId的格式，对于sandbox模式，ip始终为0.0.0.0（除非需要指定宿主机创建）。 | 见文末             |
| ucloud_vpc3_grey    | 是否开启VPC3灰度。如果要测试VPC3则填true（视机房VPC3灰度情况决定最终是否生效）。                                                                 | false           |

![](media/utest-5.png)

点击**报告**即可打开测试报告详情：

![](media/utest-7.png)

## 预发布2如何进行VPC测试

预发布2有两套测试环境，分别为VPC2和VPC3，分属于不同SET，测试时根据情况如下填写：

| 属性                  | VPC2         | VPC3             |
| ------------------- | ------------ | ---------------- |
| ucloud_uhost_ip_set | 0.0.0.0:2    | 0.0.0.0:1(或留空默认) |
| ucloud_vpc3_grey    | false(或留空默认) | true             |

---

**sandbox模式集群分布**

| Region | SET ID（集群） | 环境              | ucloud_uhost_ip_set | 后端宿主机                             |
| ------ | ---------- | --------------- | ------------------- | --------------------------------- |
| cn-gd  | 1          | VPC2 + VPC3兼容模式 | 0.0.0.0:1           | 172.27.37.114<br/>172.27.37.113   |
| cn-gd  | 2          | VPC2模式          | 0.0.0.0:2           | 172.27.33.77<br/>172.27.33.72     |
| cn-gd  | 3          | 纯VPC3模式         | 0.0.0.0:3           | 172.18.210.114<br/>172.18.210.113 |
| pre02  | 1          | VPC2 + VPC3兼容模式 | 0.0.0.0:1           | 10.64.72.13<br/>10.64.72.12       |
| pre02  | 2          | VPC2模式          | 0.0.0.0:2           | 10.64.72.3<br/>10.64.72.2         |
| pre02  | 3          | 纯VPC3模式         | 0.0.0.0:3           | 10.64.81.138<br/>10.64.81.140     |
