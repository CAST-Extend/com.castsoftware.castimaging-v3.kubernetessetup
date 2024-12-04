{{- define "my-app.configmap-selector" -}}
{{- $podName := .Values.podNameOverride | default .Values.podName | default .Release.Name -}}
{{- $ordinal := (regexFind "[0-9]+$" $podName) | int -}}
{{- if eq $ordinal 0 -}}
  configmap-for-ordinal-0
{{- else if eq $ordinal 1 -}}
  configmap-for-ordinal-1
{{- else if eq $ordinal 2 -}}
  configmap-for-ordinal-2
{{- end -}}
{{- end -}}