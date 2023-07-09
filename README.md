# Observability Architecture Helm Chart

This model is designed to collect spans through OpenTelemetry independent collectors (DaemonSets by default) and/or side car collectors. Those traces can be later explored  in Grafana.

There's also a collection of Elasticsearch nodes for general purpose and an Elastic Agent to scrape cluster metrics through a Kube State Metrics instance whose data can be visualized in Kibana.

Keep in mind that the architecture isn't limited its predefined structure. You modify the way you want. It was made with extensibility in mind.

## Prerequesites

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

The installation process shown above automatically generates a certificate so the API server can access the webhook component. There're other ways to install. Take a look at the [TLS Certificate Requirement](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-operator#tls-certificate-requirement) section in the Operator chart directory.

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

As mentioned previously, it can collect spans through sidecar containers or by a set of independently deployed collectors (DaemonSet by default).

In turn, those collectors forward the spans to the Jaeger Collector and runs them through a processing pipeline (validates and performs transformations). After that, it publishes them in Kafka so the Injester can read, index and store in the storage backend, Elasticsearch (independent of the one used by the ECK stack).

Through the Jaeger Query component, you can use Grafana to visualize the produced traces.

### General Purpose ECK Stack

All data ingested into Elasticsearch can be visualized on Kibana.

TODO

### Backend storage design

Both Tracing System and General Purpose ECK Stack follow the same backend structure. It's deployed as a StatefulSet hot-warn-cold architecture with dedicated node(s) which controls the system. Know more about Elasticsearch node roles and orchestration [here](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html).

### Scalability

The current settings aren't prepared for a production environment. See the [Fine-tune](#fine-tune) for how extend the resources and the number of nodes per component.

## Exposed services

TODO

### Istio Gateway

TODO

## Fine-tune

TODO

