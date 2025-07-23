#!/bin/bash

# Bu script HAProxy sunucuda çalıştırılacak.
# Tüm alt yapı kurulduktan ve HAProxy sunucuda tüm servis podlarının running olduğu görüldükten sonra uygulanacak.
  
## İlk komutl harbor'da image artifact'lerin depolanması için bir project oluşturuyor.
## username ve password barındırdığı için her hangi bir github repoya gönderilmedi
## Manuel de yapabilirdi ama hızlı olması için bu şekilde yapıldı.
curl -k -u username:'password' -X POST "https://harbor.xxxxxx.com/api/v2.0/projects" \
  -H "Content-Type: application/json" \
  -d '{
    "project_name": "example",
    "public": false
}'

## Uygulamanın harbor'dan image'leri çekebilmesi için imagePullPolicy olarak docker-registry secret oluşturmak gerekiyor.
## Aynı şekilde harbor username ve password barındırdığı için github repoya gönderilmedi.
kubectl create secret docker-registry harbor-pull-secret \
  --docker-server=harbor.xxxxxxx.com \
  --docker-username=harbor_username \
  --docker-password=xxxxxxxxxxx \
  --docker-email=e-mail \
  -n dev

kubectl create secret docker-registry harbor-pull-secret \
  --docker-server=harbor.xxxxxxx.com \
  --docker-username=harbor_username \
  --docker-password=xxxxxxxxxxx \
  --docker-email=e-mail \
  -n prod

## Uygulamanın connection-stringleri manuel olarak vault'a  portaldan girilebilirdi ama 
## Aynı şekilde postgresql database, username ve password barındığı için github repoya gönderilmedi.
kubectl exec -n vault vault-0 -- /bin/sh -c '
vault kv put secret/dev/appsettings appsettings.json='\''
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*",
  "ConnectionStrings": {
    "DefaultConnection": "Host=postgresql.postgresql.svc.cluster.local;Port=5432;Database=mkanus;Username=mkanus;Password=mkanus123"
  }
}'\'''

# Prod için:
kubectl exec -n vault vault-0 -- /bin/sh -c '
vault kv put secret/prod/appsettings appsettings.json='\''
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*",
  "ConnectionStrings": {
    "DefaultConnection": "Host=postgresql.postgresql.svc.cluster.local;Port=5432;Database=mkanus;Username=mkanus;Password=mkanus123"
  }
}'\'''

## Yukarıdaki komutlar çalıştırıldıktan sonra argocd portalından sidebar'dan Settings/Repositories/ConnectRepo
## kısmından github username ve github_token ile manifest dosyalarının olduğu repo eklenecek. (repo private olduğu için)
## Private repo tanıtıldıktan sonra portaldan todoapp-dev ve todoapp-prod adından aplications oluşturulacak.