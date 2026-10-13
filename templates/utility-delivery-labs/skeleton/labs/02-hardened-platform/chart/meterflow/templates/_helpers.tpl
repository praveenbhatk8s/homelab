{{- define "meterflow.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "meterflow.labels" -}}
app.kubernetes.io/name: meterflow
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "meterflow.selectorLabels" -}}
app.kubernetes.io/name: meterflow
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* The pod and container security settings from ADR-002. Do not add runAsUser:
     OpenShift assigns a UID from the namespace range, and the image runs as any non-root UID. */}}
{{- define "meterflow.podSecurityContext" -}}
runAsNonRoot: true
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "meterflow.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end -}}
