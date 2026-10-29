{{/*
Short hash suffix for one-shot Job names. A Job's spec.template is immutable, so changing it in place
(helm upgrade, or Argo CD even with Replace=true) is rejected. Changing the name whenever the chart version,
the values or the Job's script change makes Helm/Argo CD create a new Job and prune the old one instead of
patching it.

Usage: include "imaging.jobSuffix" (list . "<configmap template file>" "<script key>")
The script is read from the rendered ConfigMap, so only that key is hashed: editing another script of the
same ConfigMap does not re-run the Job.
*/}}
{{- define "imaging.jobSuffix" -}}
{{- $root := index . 0 -}}
{{- $script := "" -}}
{{- if gt (len .) 2 -}}
{{- $key := index . 2 -}}
{{- $rendered := include (printf "%s/%s" $root.Template.BasePath (index . 1)) $root -}}
{{- range regexSplit "(?m)^---\\s*$" $rendered -1 -}}
{{- $doc := fromYaml . -}}
{{- if and $doc.data (hasKey $doc.data $key) -}}
{{- $script = index $doc.data $key -}}
{{- end -}}
{{- end -}}
{{- if not $script -}}
{{- fail (printf "imaging.jobSuffix: key %q not found in %s" $key (index . 1)) -}}
{{- end -}}
{{- end -}}
{{- printf "%s-%s-%s" $root.Chart.Version (toYaml $root.Values) $script | sha256sum | trunc 8 -}}
{{- end -}}
