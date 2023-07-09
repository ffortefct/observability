# Observability Architecture Helm Chart

This model is designed to collect spans through OpenTelemetry independent collectors (DaemonSets by default) and/or side car collectors. Those traces can be later explored  in Grafana.

There's also a collection of Elasticsearch nodes for general purpose and an Elastic Agent to scrape cluster metrics through a Kube State Metrics instance whose data can be visualized in Kibana.

Both Kibana and Grafana can be exposed with a Istio Gateway.

Keep in mind that the architecture isn't limited its predefined structure. You modify the way you want. It was made with extensibility in mind.

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
- [Fine-tune](#fine-tune)

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

Given the Jaeger Query, you can use Grafana to visualize the produced traces.

There're two CronJobs in charge of maintain the backend storage:
  - **Index Cleaner**: garbage collects older indexes based on a given schedule;
  - **Rollover**: rolls the write alias to a new index with a given schedule on supplied conditions (passed by an environment variable - CONDITIONS). See the [Rollover API](https://www.elastic.co/guide/en/elasticsearch/reference/master/indices-rollover-index.html#indices-rollover-index) to know how to create conditions that meet your intentions.

Schedules of both components follow the Kubernetes [Schedule syntax](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/#schedule-syntax).

### General Purpose ECK Stack

All data sent to Elasticsearch can be visualized on Kibana.

There're Elastic Agents (deployed as a DaemonSet in every Kubernetes cluster node) which collect cluster metrics from a Kube State Metrics instance. Those agents are managed by a Fleet Server. You can manage those agents through Kibana.

### Backend Storage Design

Both Tracing System and General Purpose ECK Stack follow the same backend structure. It's deployed as a StatefulSet hot-warn-cold architecture with master node(s) that control the system. Know more about Elasticsearch node roles and orchestration [here](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-node.html).

### Scalability Considerations

The current settings aren't prepared for a production environment. See the [Fine-tune](#fine-tune) section for how to extend the resources and the number of nodes per component.

## Exposed services

### DNS Names

TODO

### Istio Gateway

TODO

## Fine-tune

TODO

TODO notes:
  - increase fleet server number of replicas when the number of k8s nodes increase.

