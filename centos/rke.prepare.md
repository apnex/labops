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
```
./argo.password.sh 'VMware1!SDDC'
```
