### install local-path-provisioner
```
cd storage
./storage.install.sh
cd ..
```

### install metallb
```
cd metallb
./metallb.install.sh
./metallb.prepare.sh
cd ..
``` 

---
### install argocd
```
cd argo
./argo.install.sh
./argo.service.sh
```

### install argocd cli
```
./argo.cli.install.sh
```

### update argocd admin password
Adjust to be a full password reset via configmap
```
./argo.password.sh 'VMware1!SDDC'
```

kubectl -n kube-system get deployments -o json
