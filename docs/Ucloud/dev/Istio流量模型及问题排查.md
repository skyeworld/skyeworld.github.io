# Istio流量模型及问题排查

<p align="right"><font color=Grey>孙鑫 2020-10-29</font></p>

## Istio 流量模型

<img title="" src="media/96c756a6013721fec26c08d9ad9ea76746e2fbbb.png" alt="" data-align="left">

### Sidecar 配置方式

- 自动注入
  
  - sidecar：流量代理
  - initContainer：根据应用设置 iptables 规则

- 手动注入
  
  - sidecar

- 配置文件
  
  - 注入前
  
  ```yaml
  apiVersion: v1
  kind: Service
  metadata:
    name: productpage
    labels:
      app: productpage
  spec:
    ports:
    - port: 9080
      name: http
    selector:
      app: productpage
  ---
  apiVersion: extensions/v1beta1
  kind: Deployment
  metadata:
    name: productpage-v1
  spec:
    replicas: 1
    template:
      metadata:
        labels:
          app: productpage
          version: v1
      spec:
        containers:
        - name: productpage
          image: istio/examples-bookinfo-productpage-v1:1.8.0
          imagePullPolicy: IfNotPresent
          ports:
          - containerPort: 9080
  ```
  
  - 注入后
  
  ```yaml
  apiVersion: v1
  kind: Service
  metadata:
    name: productpage
    labels:
      app: productpage
  spec:
    ports:
    - port: 9080
      name: http
    selector:
      app: productpage
  ---
  apiVersion: extensions/v1beta1
  kind: Deployment
  metadata:
    creationTimestamp: null
    name: productpage-v1
  spec:
    replicas: 1
    strategy: {}
    template:
      metadata:
        annotations:
          sidecar.istio.io/status: '{"version":"fde14299e2ae804b95be08e0f2d171d466f47983391c00519bbf01392d9ad6bb","initContainers":["istio-init"],"containers":["istio-proxy"],"volumes":["istio-envoy","istio-certs"],"imagePullSecrets":null}'
        creationTimestamp: null
        labels:
          app: productpage
          version: v1
      spec:
        containers:
        - image: istio/examples-bookinfo-productpage-v1:1.8.0
          imagePullPolicy: IfNotPresent
          name: productpage
          ports:
          - containerPort: 9080
          resources: {}
        - args:
          - proxy
          - sidecar
          - --configPath
          - /etc/istio/proxy
          - --binaryPath
          - /usr/local/bin/envoy
          - --serviceCluster
          - productpage
          - --drainDuration
          - 45s
          - --parentShutdownDuration
          - 1m0s
          - --discoveryAddress
          - istio-pilot.istio-system:15007
          - --discoveryRefreshDelay
          - 1s
          - --zipkinAddress
          - zipkin.istio-system:9411
          - --connectTimeout
          - 10s
          - --statsdUdpAddress
          - istio-statsd-prom-bridge.istio-system:9125
          - --proxyAdminPort
          - "15000"
          - --controlPlaneAuthPolicy
          - NONE
          env:
          - name: POD_NAME
            valueFrom:
              fieldRef:
                fieldPath: metadata.name
          - name: POD_NAMESPACE
            valueFrom:
              fieldRef:
                fieldPath: metadata.namespace
          - name: INSTANCE_IP
            valueFrom:
              fieldRef:
                fieldPath: status.podIP
          - name: ISTIO_META_POD_NAME
            valueFrom:
              fieldRef:
                fieldPath: metadata.name
          - name: ISTIO_META_INTERCEPTION_MODE
            value: REDIRECT
          image: jimmysong/istio-release-proxyv2:1.0.0
          imagePullPolicy: IfNotPresent
          name: istio-proxy
          resources:
            requests:
              cpu: 10m
          securityContext:
            privileged: false
            readOnlyRootFilesystem: true
            runAsUser: 1337
          volumeMounts:
          - mountPath: /etc/istio/proxy
            name: istio-envoy
          - mountPath: /etc/certs/
            name: istio-certs
            readOnly: true
        initContainers:
        - args:
          - -p
          - "15001"
          - -u
          - "1337"
          - -m
          - REDIRECT
          - -i
          - '*'
          - -x
          - ""
          - -b
          - 9080,
          - -d
          - ""
          image: jimmysong/istio-release-proxy_init:1.0.0
          imagePullPolicy: IfNotPresent
          name: istio-init
          resources: {}
          securityContext:
            capabilities:
              add:
              - NET_ADMIN
            privileged: true
        volumes:
        - emptyDir:
            medium: Memory
          name: istio-envoy
        - name: istio-certs
          secret:
            optional: true
            secretName: istio.default
  status: {}
  ```

### 原生流量代理

- 入向流量
  1. 入向流量进入 POD 直接被 iptables 拦截，根据 iptables 内的规则匹配到目的端口是服务端口的数据包都重定向往 sidecar；
  2. sidecar 根据其内部的转发规则（route/cluster/endpoint）进行判断，决定是否允许将数据包转发到后端应用，如果允许的话其发出的流量被 iptables 再次拦截；
  3. iptables 拦截到该数据包后发现是 uid=envoy 的，则将该数据包直接送往应用进程；
- 出向流量
  1. 应用发出的出向流量直接被 iptables 拦截；
  2. iptables 根据转发规则发现只要目的地址不等于 `127.0.0.1` 的数据包都重定向到 sidecar；
  3. sidecar 根据其内部的转发规则（route/cluster/endpoint）进行判断，决定是否允许将数据包转发到后端应用以及后代应用的真实 ip，如果允许的话其发出的流量被 iptables 再次拦截；
  4. iptables 拦截到该数据包后发现是 uid=envoy 的，则将该数据包直接送往真实目的地址；

### 简化后模型

- 入向流量
  1. 入向流量进入 POD 后不再被拦截，直接送往目的端口
- 出向流量
  1. 应用发送的请求被代理到 sidecar；
  2. sidecar 根据转发规则判断是否进行转发，如果转发则根据路由规则直接送往目的地址；

```go
    if host, _, e := net.SplitHostPort(target); e != nil || nil == net.ParseIP(host) {
        // If target is IP address, directly dial it
        if 0 != cfg.WithProxyPort && app.isSameNamespace(host) {
            dialer := func(ctx context.Context, addr string) (net.Conn, error) {
                var lo string
                if len(app.LocalIP) == net.IPv4len {
                    lo = "127.0.0.1"
                } else {
                    lo = "[::1]"
                }
                proxy := fmt.Sprintf("%s:%d", lo, cfg.WithProxyPort)
                app.Infof("dial by %s", proxy)
                d := net.Dialer{}
                return d.DialContext(ctx, "tcp", proxy)
            }
            options = append(options, grpc.WithContextDialer(dialer))
        }
    }

    return grpc.DialContext(ctx, target, options...)
```

### 带来的流量治理功能

- 负载均衡
  - round_robin：轮询算法，默认
  - random：随机从健康的后端节点随机选取一个
  - least_connection：最少链接算法，从两个随机选取的后端实例选择一个活动请求数最少的实例
  - passthrough：直接转发到以连接的目标地址，即无负载均衡
  - consistentHash：一致性哈希，只对http请求有效，基于 header、cookie 的取值进行哈希，把结果一致的请求送往相同的后端实例上
- 路由管理
  - 路由匹配条件（基于 header、uri、port、method、scheme、authority、labels）
  - 目的集群流量权重分配
  - http 重写
  - http 重定向
  - 请求重试
  - 错误注入
  - 流量镜像
  - header 操作
  - 路由管理
    - 金丝雀发布
    - 蓝绿发布
    - A/B测试
- 超时
- 重试
- 熔断
- 限流

### 路由管理

- 资源定义
  - route（每一条路由规则）
  - cluster（每一个集群，即 deployment）
  - endpoint（每一个 pod）
- 请求该怎么走，详见[官网](https://istio.io/latest/docs/reference/config/networking/virtual-service/#HTTPMatchRequest)

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  annotations:
    Platform: Karthus
    default_subsets: '["s1"]'
  creationTimestamp: null
  name: dpmgr
  namespace: prj-vnpd-vpc3
spec:
  exportTo:
  - .
  gateways:
  - mesh
  - gateway
  hosts:
  - gateway
  - dpmgr
  - gateway.prj-vnpd-vpc3
  - gateway.prj-vnpd-vpc3.kunsvc.a2.uae
  http:
  - match:
    - uri:
        prefix: /dpmgr/metrics
    name: dpmgr-metrics
    rewrite:
      uri: /metrics
    route:
    - destination:
        host: dpmgr
        port:
          number: 81
        subset: s1
      weight: 100
  - match:
    - uri:
        prefix: /dpmgr/admin
    name: dpmgr-admin
    rewrite:
      uri: /admin
    route:
    - destination:
        host: dpmgr
        port:
          number: 81
        subset: s1
      weight: 100
  - match:
    - uri:
        prefix: /dpmgr/debug
    name: dpmgr-debug
    rewrite:
      uri: /debug
    route:
    - destination:
        host: dpmgr
        port:
          number: 81
        subset: s1
      weight: 100
  - match:
    - uri:
        prefix: /datapath.Manager
    name: dpmgr.prj-vnpd-vpc3
    retries: {}
    route:
    - destination:
        host: dpmgr
        port:
          number: 80
        subset: s1
      weight: 100
  - match:
    - uri:
        prefix: /datapath.ManagerAdminService
    name: dpmgr-admin.prj-vnpd-vpc3
    route:
    - destination:
        host: dpmgr
        port:
          number: 80
        subset: s1
      weight: 100
```

- 流量到了之后该怎么办，详见[官网](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-TCPSettings)

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  annotations:
    Platform: Karthus
    version: v0.4.3
  creationTimestamp: null
  name: dpmgr-s1
  namespace: prj-vnpd-vpc3
spec:
  host: dpmgr
  subsets:
  - labels:
      cluster: s1
    name: s1
    trafficPolicy:
      connectionPool:
        http:
          http1MaxPendingRequests: 10000        #最大 pending 的 http 请求数
          http2MaxRequests: 10000                        #对后端请求的最大数量
        tcp:
          connectTimeout: 0.030s                        #TCP 连接超时时间
          maxConnections: 10000                            #到目的主机的最大连接数
          tcpKeepalive:
            interval: 75s
            time: 7200s
      loadBalancer:
        simple: LEAST_CONN
```

## ServiceMesh故障排查

- namespace 间：查看 gateway 日志，看请求是否转发到后端

```ini
[2020-10-28T17:22:56.894Z] "POST /services.EventService/DescribeAccountVersions HTTP/2" 200 - "-" 11 20 1 0 "2002:ac1b:7f58:1:0:24:aae:3b2" "grpc-go/1.23.0" "3d9a8038-21a2-91bb-981f-a9b3599cf70e" "gateway.prj-vnpd-vpc3:8080" "[2002:ac1b:7f58:1:0:ff:aae:60]:7000" outbound|80|s2|evt-service.prj-vnpd-vpc3.svc.a2.uae - [2002:ac1b:7f58:1:0:ff:aae:1b]:8080 [2002:ac1b:7f58:1:0:24:aae:3b2]:43356 -
```

![](media/fa3db5c3c3edd6a9c5f4ceb8483dee3d48e48dfb.png)

- namespace 内：查看 client 端的 sidecar 日志，看请求是否转发到后端
- 常见状态码标志位，详情见[官网](https://www.envoyproxy.io/docs/envoy/v1.16.0/configuration/observability/access_log/usage)：
  - HTTP and TCP
    - **UH**: No healthy upstream hosts in upstream cluster in addition to 503 response code.
    - **UF**: Upstream connection failure in addition to 503 response code.
    - **UO**: Upstream overflow ([circuit breaking](https://www.envoyproxy.io/docs/envoy/v1.16.0/intro/arch_overview/upstream/circuit_breaking#arch-overview-circuit-break)) in addition to 503 response code.
    - **NR**: No [route configured](https://www.envoyproxy.io/docs/envoy/v1.16.0/intro/arch_overview/http/http_routing#arch-overview-http-routing) for a given request in addition to 404 response code, or no matching filter chain for a downstream connection.
    - **URX**: The request was rejected because the [upstream retry limit (HTTP)](https://www.envoyproxy.io/docs/envoy/v1.16.0/api-v3/config/route/v3/route_components.proto#envoy-v3-api-field-config-route-v3-retrypolicy-num-retries) or [maximum connect attempts (TCP)](https://www.envoyproxy.io/docs/envoy/v1.16.0/api-v3/extensions/filters/network/tcp_proxy/v3/tcp_proxy.proto#envoy-v3-api-field-extensions-filters-network-tcp-proxy-v3-tcpproxy-max-connect-attempts) was reached.
  - HTTP only
    - **DC**: Downstream connection termination.
    - **LH**: Local service failed [health check request](https://www.envoyproxy.io/docs/envoy/v1.16.0/intro/arch_overview/upstream/health_checking#arch-overview-health-checking) in addition to 503 response code.
    - **UT**: Upstream request timeout in addition to 504 response code.
    - **LR**: Connection local reset in addition to 503 response code.
    - **UR**: Upstream remote reset in addition to 503 response code.
    - **UC**: Upstream connection termination in addition to 503 response code.
    - **DI**: The request processing was delayed for a period specified via [fault injection](https://www.envoyproxy.io/docs/envoy/v1.16.0/configuration/http/http_filters/fault_filter#config-http-filters-fault-injection).
    - **FI**: The request was aborted with a response code specified via [fault injection](https://www.envoyproxy.io/docs/envoy/v1.16.0/configuration/http/http_filters/fault_filter#config-http-filters-fault-injection).
    - **RL**: The request was ratelimited locally by the [HTTP rate limit filter](https://www.envoyproxy.io/docs/envoy/v1.16.0/configuration/http/http_filters/rate_limit_filter#config-http-filters-rate-limit) in addition to 429 response code.
    - **UAEX**: The request was denied by the external authorization service.
    - **RLSE**: The request was rejected because there was an error in rate limit service.
    - **IH**: The request was rejected because it set an invalid value for a [strictly-checked header](https://www.envoyproxy.io/docs/envoy/v1.16.0/api-v3/extensions/filters/http/router/v3/router.proto#envoy-v3-api-field-extensions-filters-http-router-v3-router-strict-check-headers) in addition to 400 response code.
    - **SI**: Stream idle timeout in addition to 408 response code.
    - **DPE**: The downstream request had an HTTP protocol error.
    - **UMSDR**: The upstream request reached to max stream duration.
