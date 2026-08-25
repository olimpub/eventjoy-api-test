# EventJoy API - Publikálási és Git parancsok

Ebből a fájlból bármikor kimásolhatod a deploy-hoz és verziókövetéshez szükséges terminál parancsokat.

## 1. Publikálás Azure-ba (Azure Functions)

Ha terminálból szeretnéd egyenesen feltolni a kódot az Azure-ba, a legegyszerűbb az **Azure Functions Core Tools** használata. 

A projekt gyökerében (ahol a `.csproj` fájl is van) futtasd a következőt:

```powershell
func azure functionapp publish <AZURE_FÜGGVÉNYAPP_NEVE>
```
*(Cseréld ki a `<AZURE_FÜGGVÉNYAPP_NEVE>` részt a tényleges Azure-os alkalmazásod nevére, pl. `eventjoy-api-test`)*

### Alternatíva: Zip Deploy (Azure CLI segítségével)
Ha az Azure CLI-t (az) használod:
```powershell
dotnet publish -c Release
Compress-Archive -Path .\bin\Release\net10.0\publish\* -DestinationPath .\deploy.zip -Force
az functionapp deployment source config-zip -g <RESOURCE_GROUP_NEVE> -n <AZURE_FÜGGVÉNYAPP_NEVE> --src .\deploy.zip
```


## 2. Kód mentése Git-re (ha Azure-on már minden működik)

Ha tesztelted az Azure-on és rendben van a kód, a következő lépésekkel tudod beküldeni a git repository-ba:

**Módosítások hozzáadása:**
```powershell
git add .
```

**Commit (mentés) egy rövid leírással:**
```powershell
git commit -m "Fix: Social login dynamic results handling"
```

**Feltöltés a távoli (GitHub / Azure DevOps / GitLab) szerverre:**
```powershell
git push
```
