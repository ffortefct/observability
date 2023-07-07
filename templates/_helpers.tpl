{{/*
Allows overriding namespace with namespaceOverride.
*/}}
{{- define "observability.namespace" -}}
{{- if .Values.namespaceOverride }}
{{- .Values.namespaceOverride }}
{{- else }}
{{- .Release.Namespace }}
{{- end }}
{{- end }}

