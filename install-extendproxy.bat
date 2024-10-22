@echo off
set NAMESPACE=castimaging-v3
echo **********************************************************************************************
echo Extendproxy setup (optional):
echo **********************************************************************************************
echo     - Rename template/ex_extendproxy-service.yaml into template/extendproxy-service.yaml
echo     - Apply helm chart changes:
echo         run "helm upgrade castimaging-v3 --namespace %NAMESPACE% --set version=3.0.0 ."
echo     - Get the extendproxy service EXTERNAL-IP:
echo         run "kubectl get service -n castimaging-v3 extendproxy"
echo         For instance: a33300000000004523be8231c11431899-1907755555.us-east-2.elb.amazonaws.com
echo     - Update the exthostname variable in values.yaml with this value, for instance:
echo        ExtendProxy:
echo          exthostname: a33300000000004523be8231c11431899-1907755555.us-east-2.elb.amazonaws.com
echo     - Rename template/ex_extendproxy-deployment.yaml into template/extendproxy-deployment.yaml
echo     - Apply helm chart changes:
echo         run "helm upgrade castimaging-v3 --namespace %NAMESPACE% --set version=3.0.0 ."
echo     - Review the log of the extendproxy pod to see the administration URL and extend token
echo **********************************************************************************************
