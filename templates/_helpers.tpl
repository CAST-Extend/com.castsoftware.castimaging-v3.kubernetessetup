{{/*
Returns "true" when containers run with a read-only root filesystem, "false" otherwise.
Only applies when RestrictedSecurityMode is true. RestrictedSecurityModeReadOnly defaults to true when not set.
When "false", the writable emptyDir volumes and the init containers copying image files into them are not created.
*/}}
{{- define "imaging.readOnlyRootFS" -}}
{{- if and .Values.RestrictedSecurityMode (ne (toString .Values.RestrictedSecurityModeReadOnly) "false") -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Short hash suffix for one-shot Job names. A Job's spec.template is immutable, so changing it in place
(helm upgrade, or Argo CD even with Replace=true) is rejected. Changing the name whenever the chart version
or values change makes Helm/Argo CD create a new Job and prune the old one instead of patching it.
*/}}
{{- define "imaging.jobSuffix" -}}
{{- printf "%s-%s" .Chart.Version (toYaml .Values) | sha256sum | trunc 8 -}}
{{- end -}}
