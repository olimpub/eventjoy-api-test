# SignalR & Service Bus Integrációs Terv (Hotload Architektúra)

Ez a dokumentum lépésről lépésre végigvezet azon, hogyan építjük be a rendszerbe a valós idejű (SignalR) értesítéseket az Azure Service Bus közvetítésével, **Hotload** (tárolt eljárásból azonnal érkező payload) módszertannal.

---

## 1. Előfeltételek (Prerequisites) és Azure Beállítások

### 1.1 Azure SignalR Service Létrehozása
1. Az Azure Portalon hozz létre egy **SignalR Service** erőforrást.
2. **Kritikus:** A *Service Mode* fülön válaszd a **Serverless** opciót!
3. Másold ki a *Connection String*-et (Keys menüpont), és tedd be a lokális fejlesztéshez a `local.settings.json`-be:
   ```json
   "AzureSignalRConnectionString": "Endpoint=https://..."
   ```

### 1.2 Azure Service Bus Topic és Subscription beállítása
Mivel említetted, hogy a `communication` (Topic) alatt már ott a `signalr` (Subscription), a következőt kell ellenőrizned az Azure Portalon (vagy Service Bus Explorerben):
1. Navigálj a `communication` topic -> `signalr` subscription részhez.
2. Keresd meg a **Filters** (Szűrők) beállítást.
3. Győződj meg róla, hogy van egy **SQL Filter** beállítva, amelynek a feltétele pontosan ez:
   ```sql
   channel = 'signalr'
   ```
   *(Erre azért van szükség, hogy a SignalR feliratkozás ne kapja meg a kiküldendő e-maileket, és az e-mail küldő ne kapja meg a SignalR üzeneteket.)*

---

## 2. Megvalósítás Backend (API) Oldalon

### 2.1 NuGet Csomagok Telepítése
A terminálban, a backend projekt mappájában futtasd le:
```bash
dotnet add package Microsoft.Azure.Functions.Worker.Extensions.SignalRService
```

### 2.2 Kliens Csatlakozás (Negotiate) és Csoportkezelés
Létre kell hozni egy `SignalREndpoints.cs` fájlt, amiben két alapvető végpont lesz:
1. **`/api/negotiate`**: A frontend ide csatlakozik be, ez adja vissza a tokent, amivel a kliens fel tud lépni a SignalR WebSocket-re.
2. **`/api/event/join`**: Miután a frontend csatlakozott, meghívja ezt a végpontot a kiválasztott `EventID`-vel. A backend ezen a végponton keresztül beteszi a klienst (a kapcsolatát) az `event_{id}` nevű csoportba (Group), hogy a megfelelő esemény értesítéseit kapja csak meg.

### 2.3 SQL Tárolt Eljárások (SP) Módosítása (Hotload)
Bármelyik SP, ami állapotos változást végez (pl. `spChangeEvent`, `spImportInvitations`), kiegészül egy új **Result Set**-tel.
A tranzakció végén az SQL egyből legenerálja a kiküldendő JSON-t:

```sql
-- Példa a tranzakció végére:
SELECT 
    'event_' + CAST(@EventID AS VARCHAR) AS TargetGroup,
    'EventStatusChanged' AS EventName,
    (SELECT EventID, EventStatusID FROM [EJ].[tblEvent] WHERE ID = @EventID FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS PayloadJson;
```

### 2.4 C# Végpontok (Endpoints) Kiegészítése
Azokban az API végpontokban (pl. `EventEndpoints.cs`), ahol a módosító SP-ket hívjuk, kiolvassuk az új Result Set-et.
Ha van benne adat, azonnal bedobjuk a Service Bus-ba:

```csharp
var sbMessage = new Azure.Messaging.ServiceBus.ServiceBusMessage(hotloadData.PayloadJson)
{
    MessageId = Guid.NewGuid().ToString()
};
sbMessage.ApplicationProperties["channel"] = "signalr";
sbMessage.ApplicationProperties["targetGroup"] = hotloadData.TargetGroup;
sbMessage.ApplicationProperties["eventName"] = hotloadData.EventName;

await sender.SendMessageAsync(sbMessage);
```
*Fontos: Ezáltal a HTTP válasz azonnal kimegy a hívónak, nem akadunk fent a SignalR hálózati késésein.*

### 2.5 A Háttérfolyamat (SignalRRouterFunction) Létrehozása
Ez lesz az az új Azure Function munkás, aki a buszról olvassa a feladatokat és kiabál a SignalR-en keresztül a klienseknek.
- **Trigger**: `[ServiceBusTrigger("communication", "signalr")]`
- **Működése**: Megkapja az üzenetet a buszról, kiolvassa a metaadatokból a `targetGroup`-ot és az `eventName`-et, és az output binding segítségével (vagy a menedzsment SDK-val) kiküldi a payloadot a SignalR Service-nek, ami továbbítja azt a megfelelő csoportba lépett klienseknek.

---

## 3. Frontend Lépések (Kliens)

A frontend fejlesztőnek a következőket kell tennie ( `@microsoft/signalr` csomaggal):
1. **Csatlakozás**: Kapcsolat nyitása a backend `/api` útvonalán keresztül.
2. **Csatlakozás a Csoporthoz**: A sikeres kapcsolódás után egy REST hívás a `/api/event/join?eventId=42` végpontra (vagy a belépés részeként, ahogy kialakítjuk).
3. **Események figyelése**:
   ```javascript
   connection.on("EventStatusChanged", (data) => {
       console.log("Státusz megváltozott:", data.EventStatusID);
       // UI frissítése a hotload adat alapján
   });
   ```

---
**Ha a fentiekkel megvagy (SignalR az Azure-ban él, SQL Filter a Buszon be van állítva, csomag felrakva), szólj, és azonnal megírom a szükséges C# kódot a backendbe!**
