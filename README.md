# Observability Architecture Helm Chart

This model is designed to collect spans through OpenTelemetry independent collectors and/or sidecar collectors. Those traces can be later explored in Grafana.

There's also a collection of Elasticsearch nodes for general purpose and Elastic Agents to scrape cluster metrics through a Kube State Metrics instance whose data can be visualized in Kibana.

Both Kibana and Grafana can be exposed with an Istio Gateway.

The architecture isn't limited to its current structure. You can extend and modify the way you want.

## Table Of Contents

- [Prerequisites](#prerequisites)
- [Installing the Operator(s)](#installing-the-operator(s))
  - [ECK](#eck)
  - [OpenTelemetry](#opentelemetry)
- [Installing the Chart](#installing-the-chart)
- [Architecture Overview](#architecture-overview)
  - [Tracing System](#tracing-system)
  - [General Purpose ECK Stack](#general-purpose-eck-stack)
  - [Backend Storage Design](#backend-storage-design)
  - [Scalability Considerations](#scalability-considerations)
- [Exposed Services](#exposed-services)
  - [DNS Names](#dns-names)
  - [Istio Gateway](#istio-gateway)
- [OpenTelemetry Collector](#opentelemetry-collector)
  - [Independent](#independent)
  - [Sidecar Container](#sidecar-container)
- [Fine-tune](#fine-tune)
  - [Probes](#probes)
  - [Scaling, Resources and Storage](#scaling%2C-resources-and-storage)
  - [Elasticsearch Virtual Memory](#elasticsearch-virtual-memory)
  - [Jaeger Index Auto Cleaner and Rollover](#jaeger-index-auto-cleaner-and-rollover)

## Prerequisites

- Kubernetes 1.24+
- Helm 3.9.0+
- ECK Operator
- OpenTelemetry Operator (optional - necessary for sidecar collectors)

## Installing the Operator(s)

### ECK

Add the Elastic Helm Repository:

```sh
helm repo add elastic https://helm.elastic.co && \
  helm repo update
```

Install and deploy the Operator:

```sh
helm install -n elastic-system --create-namespace \
  elastic-operator elastic/eck-operator
```

### OpenTelemetry

Add the OpenTelemetry Helm Repository:

```sh
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts && \
  helm repo update
```

Install and deploy the Operator:

```sh
helm install -n opentelemetry-operator-system --create-namespace \
  --set admissionWebhooks.certManager.enabled=false \
  --set admissionWebhooks.autoGenerateCert=true \
  opentelemetry-system open-telemetry/opentelemetry-operator
```

The installation process shown above automatically generates a certificate so the API server can access the webhook component. There're other ways to install. Take a look at the [TLS Certificate Requirement](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-operator#tls-certificate-requirement) section in the Operator chart description.

## Installing the Chart

Add the Helm Repository:

```sh
helm repo add observability https://ffortefct.github.io/observability-helm-charts && \
  helm repo update
```

Install the chart with its default values:

```sh
helm install -n observability --create-namespace \
  observability-architecture observability/architecture
```

**Always use this namespace, unless you know what you're doing.**

## Architecture Overview

### Tracing System

As mentioned previously, it's possible to collect spans through OpenTelemetry sidecar containers or by a set of independently deployed collectors (as a DaemonSet by default).

In turn, those collectors forward the spans to the Jaeger Collector and runs them through a processing pipeline (validates and performs transformations). After that, it publishes them in Kafka so the Injester can read, index and store in a storage backend - Elasticsearch (independent of the one used by the General Purpose ECK stack).

With the Jaeger Query, you can use Grafana to visualize the produced traces.

There're two CronJobs in charge of maintain the backend storage:
  - **Index Cleaner**: garbage collector for older indexes based on a given schedule;
  - **Rollover**: rolls the write alias to a new index with a given schedule on supplied conditions.

Schedules of both components follow the [Kubernetes Schedule syntax](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/#schedule-syntax).

### General Purpose ECK Stack

All data sent to Elasticsearch can be visualized in Kibana.

There're Elastic Agents (deployed as a DaemonSet) which collect cluster metrics from a Kube State Metrics instance. Those agents are managed by a Fleet Server. This control is made through Kibana.

### Backend Storage Design

Both Tracing System and General Purpose ECK Stack follow the same backend structure. It's deployed as a StatefulSet hot-warn-cold architecture with master node(s) that control the system. Know more about Elasticsearch node roles and orchestration [here](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html).

### Scalability Considerations

The current settings aren't prepared for a production environment. See the [Fine-tune](#fine-tune) section for how to extend the resources and adapt the architecture to your needs.

## Exposed services

### DNS Names

Those are the main exposed services:

- elasticsearch-eck-stk-es-http.observability.svc:9200
- otlp-independent-collector.observability.svc:4317|4318
  - 4317: gRPC
  - 4318: HTTP
- grafana.observability.svc:8080
- kibana-kb-http.observability.svc:5601

**Note:** in order to access the OpenTelemetry sidecar collector you can simply use the localhost.

### Istio Gateway

Kibana and Grafana can be exposed with an Istio Gateway by setting `istio.kibana.enabled`, `istio.grafana.enabled` to true and specify both the gateway and destination host. The host, port and path should point to the respective service to match their configs.

Besides that, you need to uncomment the following parts and set `<destination-host>` with the same host as in `istio.destinationHost`:

```yaml
...
grafana:
  grafana.ini:
    server:
      domain: "<destination-host>"
      root_url: "%(protocol)s://%(domain)s:%(http_port)s/observability/grafana"
      serve_from_sub_path: true
...
elastic-eck-stk:
  eck-kibana:
    spec:
      config:
        server.publicBaseUrl: "https://<destination-host>/observability/kibana"
        server.basePath: "/observability/kibana"
...
```

Don't forget that **the path in those fields can't end with a slash**.

Templates for virtual services and destination rules use the API version `networking.istio.io/v1beta1`.

The chart assumes that Istio is already installed and ready to use.

## OpenTelemetry Collector

### Independent

Set `otlp-independent-collector.enabled` to true if you want to use it.

### Sidecar Container

Sidecar collectors prevents from the case when one or more independent collectors are down, blocking the traffic of spans to its destination. There's a good [explanation](https://opentelemetry.io/docs/collector/scaling/#scaling-stateless-collectors) about this in the OpenTelemetry documentation.
If you intend to use this approach, you can simply enable it by setting `otlpSidecarCollector.enabled` to true. After that, set the annotation `sidecar.opentelemetry.io/inject: "observability/<otlpSidecarCollector.name>"` in the pods that you want to inject the collector like the following example:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-deployment
  labels:
    app: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      annotations:
        sidecar.opentelemetry.io/inject: "observability/otlp-sidecar-collector"
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: my-app-image:latest
```

You can also add it to the namespace. Right after the [sidecar example](https://github.com/open-telemetry/opentelemetry-operator#sidecar-injection) in the OpenTelemetry Operator README you will find an in deep explanation about this annotation.

It's possible to have both kinds of collectors at the same time. They won't interfere with each other.

## Fine-tune

### Probes

For almost every component you can adjust liveness and readiness probes (Elasticsearch has only readiness probe and Kibana doesn't have anything).

### Scaling, Resources and Storage

It is important to adjust the resources field in every possible component of the architecture. By default, the values defined in `resources.limits` and `resources.requests` are the minimum required in order to run normally.

```yaml
# Jaeger collector example:
jaeger-stack:
  collector:
    resources:
      limits:
        cpu: 1
        memory: 1Gi
      requests:
        cpu: 500m
        memory: 512Mi
```

All components are deployed with only one replica which is undesirable in a production environment.

In each Elasticsearch cluster (general purpose and Jaeger backend storage), the number of replicas and storage size per node set needs to be adjusted according to their assigned rule(s). The size of each persistent volume and amount of cpu+memory (`resources` field) is proportional to the assigned rule (e.g, `data_warm` replicas requires more storage and less resources, while `data_hot` replicas are the opposite).

If the amount of Kubernetes nodes is considerable, then you should increase the number of replicas of Kube State Metrics in `kube-state-metrics.replicas`.

In order to use a different storage class other than the default, you should set `storageClassName` and `storageClass` fields.

Jaeger injester and collector can be auto scaled if you set `jaeger-stack.injester.autoScaling.enabled` and `jaeger-stack.collector.autoScaling.enabled` to true. It's also possible to adjust the minimum and maximum number of replicas with `minReplicas` and `maxReplicas`.

### Elasticsearch Virtual Memory

Elasticsearch uses [mmap](https://en.wikipedia.org/wiki/Mmap) for efficiency purposes on accessing indexes. Seemingly, the default value used for the virtual address space on Linux Distributions is too low for Elasticsearch to run properly. So you should do the following for every node set in `elastic-jg-stk.eck-elasticsearch` and `elastic-eck-stk.eck-elasticsearch`:

```yaml
...
config:
  # Comment/remove it:
  node.store.allow_mmap: false
...
podTemplate:
  spec:
    # Uncomment this:
    initContainers:
    - command:
      - sh
      - "-c"
      - sysctl -w vm.max_map_count=262144
      name: sysctl
      securityContext:
        privileged: true
        runAsUser: 0
...
```
### Jaeger Index Auto Cleaner and Rollover

Adapt the schedule of both CronJobs (`jaeger-stack.esIndexCleaner.schedule` and `jaeger-stack.esRollover.schedule`) and set `jaeger-stack.esIndexCleaner.numberOfDays` which tells to remove indexes that are older than that value.

Conditions for Rollover are set in the environment variable `CONDITIONS` under the field `jaeger-stack.esRollover.extraEnv`. See the [Rollover API Request body](https://www.elastic.co/guide/en/elasticsearch/reference/master/indices-rollover-index.html#rollover-index-api-request-body) `conditions` specification to know more.

