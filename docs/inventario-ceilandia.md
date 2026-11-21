# Inventário do Place "Ceilandia"

Auditoria somente leitura do place **Ceilandia** (`PlaceId: 117817773230060`, nome interno `Place1`, modo `Edit`) comparada com [`AGENTS.md`](../AGENTS.md) e [`docs/design.md`](design.md).

## Metadados e configurações do place

| Propriedade / Serviço | Valor atual | Observação frente ao design |
|---|---|---|
| `Workspace.StreamingEnabled` | `true` (`MinRadius=128`, `TargetRadius=512`, `MinimumRadiusPause`, `StreamOut=Opportunistic`) | Já alinhado com `default.project.json` e meta mobile. |
| `StarterPlayer` | `EnableMouseLockOption=false`, `WalkSpeed=16`, `CharacterUseJumpPower=false`, `CameraMode=Classic` (`0.5..128`) | Shift-lock nativo desativado de propósito para o shift-lock custom (`Alt`) de `MovementClient`. |
| `Lighting` | `ClockTime=17.35`, `Brightness=3.0`, `GlobalShadows=true` + `Atmosphere`, `Bloom`, `CC_Sunset`, `DepthOfField`, `Sky`, `SunRays` | Estética pôr-do-sol pronta; validar custo de `DepthOfField`/`SunRays`/`Bloom` em celular médio. |
| `MaterialService` | `AssistantMaterials` (12 grupos `BR_*` × 4 variantes = 48 `MaterialVariant`s) | Usado pelo `District_Blockout` via `__BlockoutLib`. |
| `CollectionService` (tags de jogo) | `Destructible` (2.249), `BreakableGlass` (196), `BreakableDoor` (63), `GarageDoor` (4) | Usadas pelo sistema de destruição. |
| `TestDummy` | Rig **R6** (`MaxHealth=100`) | Confirma foco atual em R6 (assim como `PoseAnimator`). |

---

## 1. Árvore resumida por serviço

### `Workspace` (12.540 descendentes · 0 scripts)

- `Baseplate` (`Part` + `Texture`), `Camera`, `Terrain`, `SpawnLocation` (`Pos=(0, 0.5, 0)`)
- `TestDummy` (`Model` R6: `Head`, `Torso`, `Legs`, `HumanoidRootPart`, `Humanoid`)
- Peças soltas perto da origem (`Pos ≈ (-15, y, -41)`): `5 Part` + `6 UnionOperation` (sem pasta, sem tags/atributos — estrutura de teste antiga)
- `District_Blockout` (`Folder` · **12.516 descendentes**: `9.263 Part`, `1.918 MeshPart`, `5 TrussPart`, `1.052 Model`, `11 Folder`, `46 PointLight`, `68 SpotLight`, `45 SurfaceLight`, `54 SurfaceGui`/`TextLabel` · bounds aprox. `955 × 350 × 802` studs; atributos: `DestructionType=2249`, `Passable=304`, `Cover=93`, `Hinge=61`, `Type=49`, `Floors/Footprint/Size=11`):
  - `01_Roads` (`288 desc`): `Q1_Northwest` (5), `Q2_Northeast` (10), `Q3_West` (5), `Q4_Center` (10), `Q5_Southeast` (5), `RoadMarkings` (231)
  - `02_Waterfront` (`354 desc`): `BusStop` (4), `21× PalmTree` (15 cada)
  - `03_CommercialAlley` (`87 desc`): `8× VerticalSign` (7 cada)
  - `04_Cover` (`826 desc`): `ParkedCars` (450), `ParkingLotCars` (135), `Plaza` (86), `AvenueMedian` (72), `AlleysAndYards` (64), `Street` (13)
  - `05_Lighting` (`266 desc`): `39× StreetLamp`, `6× TrafficLight`, `10× WallLight`, `1× StreetFurniture`
  - `06_Background_OutOfBounds` (`1.836 desc`): `29× Edge_*`, `29× Tower`, `DistantBlocks`, `GoldHotel`
  - `Q1_Northwest` (`3.062 desc`): `ConvenienceStore` (1.195), `Building_B_Cafe` (566), `BrickBuilding_A` (546), `CornerDiner` (344), `Facade_Brick` (134), `ModernOffice` (98), `Facade_Peach` (89), `Facade_Cream` (79)
  - `Q2_Northeast` (`715 desc`): `AutoShop` (377), `Facade_AvenueCorner` (122), `OfficeTower` (102), `AutoShop_Yard` (66), `ParkingLot_North` (30), `GuardBooth` (12)
  - `Q3_West` (`1.540 desc`): `BrickBuilding_E_BarberShop` (1.195), `Facade_BlueGrey` (154), `GraffitiCorner` (98), `Facade_Sand` (69), `ParkingLot` (19)
  - `Q4_Center` (`1.951 desc`): `Bank` (658), `BrickBuilding_C` (576), `JewelryStore` (313), `Facade_Pink` (99), `Facade_White` (98), `Facade_BrickSouth` (79), `Facade_Yellow` (54), `Facade_PlazaShops` (34), `Plaza` (31)
  - `Q5_Southeast` (`1.580 desc`): `Garage_Hideout` (737), `ElectronicsStore` (458), `Building_F` (186), `Building_G` (134), `AlleyShops` (59)

### `ReplicatedStorage` (12 descendentes · 3 módulos · 6 `RemoteEvent`s)

- `Destruction` (`Folder`): `Config` (`ModuleScript`), `FXEvent` (`RemoteEvent`)
- `Remotes` (`Folder`): `GunFX`, `GunFire`, `GunHit`, `GunReload`, `PoseState` (todos `RemoteEvent`)
- `Weapons` (`Folder`): `Config` (`ModuleScript`), `Poses` (`ModuleScript`)

### `ServerScriptService` (7 descendentes · 5 scripts)

- `GunServer` (`Script`, `Enabled=true`, `RunContext=Legacy`)
- `PoseServer` (`Script`, `Enabled=true`, `RunContext=Legacy`)
- `Destruction` (`Folder`):
  - `DestructionServer` (`Script`, `Enabled=true`, `RunContext=Legacy`) → filho `DestructionTester` (`Tool`) → `TesterClient` (`LocalScript`, `Enabled=true`)
  - `DestructionService` (`ModuleScript`)

### `ServerStorage` (14 descendentes · 1 módulo)

- `ProductTemplates` (`Folder`): 12 `MeshPart`s (`CerealBox`, `Chips`, `CoffeeJar`, `Detergent`, `EnergyCan`, `GlassBottle`, `NoodleCup`, `PhoneBox`, `ShippingBox`, `SodaBottle2L`, `SodaCan`, `WaterBottle`)
- `__BlockoutLib` (`ModuleScript`)

### `StarterPack` (10 descendentes · 0 scripts)

- `M4A1` (`Tool`, `RequiresHandle=true`, `CanBeDropped=false`, atributos `Weapon="M4A1"`, `Ammo=30`, `Reloading=false`): `Handle` (`Part` → `Muzzle` `Attachment` → `Flash` `PointLight`), `Body` (`MeshPart`), `Furniture` (`MeshPart`), `Metal` (`MeshPart`), cada um com `WeldConstraint`.

### `StarterPlayer` (6 descendentes · 4 scripts)

- `StarterCharacterScripts`: `MovementClient` (`LocalScript`, `Enabled=true`, `RunContext=Legacy`)
- `StarterPlayerScripts`: `DestructionFX`, `GunClient`, `PoseAnimator` (todos `LocalScript`, `Enabled=true`, `RunContext=Legacy`)

### Outros serviços

- `Lighting` (6 efeitos/céu), `MaterialService` (61 descendentes), `TextChatService` (8 configurações padrão).
- Vazios (0 descendentes): `ReplicatedFirst`, `StarterGui`, `Teams`, `SoundService`.

---

## 2. Inventário detalhado dos scripts (13 no total)

### `ReplicatedStorage.Weapons.Config`
- **Tipo / Linhas**: `ModuleScript` · 32 linhas (`--!strict`)
- **O que faz**: Exporta o tipo `GunConfig` e define os parâmetros da arma `M4A1` (cadência `0.08s`, dano `22`, headshot `2x`, alcance `600`, carregador `30`, recarga `2.2s`, spread `0.8°`, recoil `0.6°`, multiplicador ADS `0.25`, FOV ADS `50`).
- **Remotes**: Nenhum.
- **Validação no servidor**: N/A (módulo de configuração compartilhado).

### `ReplicatedStorage.Weapons.Poses`
- **Tipo / Linhas**: `ModuleScript` · 48 linhas (`--!strict`)
- **O que faz**: Exporta o tipo `Pose`, constantes de rig R6 (`ShoulderR/L`, `ArmReach`, `MaxShoulderDetach`, `PitchPivot`), pontos da arma (`FOREGRIP`, `RAIL`, `MAGAZINE`), as 6 poses procedurais (`Idle`, `Hip`, `Aim`, `Sprint`, `Slide`, `Reload`) e a whitelist `Poses.Valid`.
- **Remotes**: Nenhum.
- **Validação no servidor**: N/A (usado por `PoseServer` como whitelist de estados).

### `ReplicatedStorage.Destruction.Config`
- **Tipo / Linhas**: `ModuleScript` · 40 linhas (sem `--!strict`)
- **O que faz**: Define 13 tipos destrutíveis (`Glass`, `Light`, `Electronics`, `Wood`, `Cardboard`, `Prop`, `Ceramic`, `Fabric`, `Leather`, `Metal`, `Door`, `MetalDoor`, `GarageDoor`) com vida, tempo de respawn, estilo de quebra, IDs de áudio e presets de partículas, além de limiares de velocidade (`CharacterBreakSpeed=42`, `VehicleBreakSpeed=18`) e teto de fragmentos (`MaxDebris=120`, `DebrisLifetime=4`).
- **Remotes**: Nenhum.
- **Validação no servidor**: N/A (módulo de configuração compartilhado).

### `ServerScriptService.GunServer`
- **Tipo / Linhas**: `Script` (`Enabled=true`, `RunContext=Legacy`) · 127 linhas (`--!strict`)
- **O que faz**: Valida disparos e recargas no servidor, consome o atributo `Ammo` da `Tool`, executa raycast a partir da `Head` (com offset lateral `SHOULDER_PEEK = 1.3` se não houver parede no caminho), aplica `TakeDamage` (2x na `Head`) e avisa o atirador (hitmarker) e os demais jogadores (VFX).
- **Remotes**: Recebe `Remotes.GunFire` (C→S) e `Remotes.GunReload` (C→S); envia `Remotes.GunHit` (S→C) e `Remotes.GunFX` (S→C).
- **Validação no servidor**: **Parcial (boa base autoritativa, mas incompleta)**. Valida tipo/finitude do `target` (`Vector3`, sem `NaN`/`inf`, componentes `< 1e6`), arma equipada, personagem vivo, `!Reloading`, cadência (`FireRate * 0.75`), `Ammo > 0` e linha de visão da cabeça/peek. **Lacunas**: sem lag compensation, sem dano por tronco/membros ou queda por distância, sem armadura nem estado derrubado, `GunReload` sem rate limit/log de abuso, `isEnemy` permite atacar `Neutral` (conflita com Civil neutro do design), `GunFX` enviado a todos sem LOD/distância, não loga tiros impossíveis e não integra destruição.

### `ServerScriptService.PoseServer`
- **Tipo / Linhas**: `Script` (`Enabled=true`, `RunContext=Legacy`) · 41 linhas (`--!strict`)
- **O que faz**: Recebe o estado de pose, pitch da mira e lado do ombro enviados pelo cliente e grava como atributos (`Pose`, `AimPitch`, `ShoulderSide`) no `Character` para que os outros clientes animem o personagem.
- **Remotes**: Recebe `Remotes.PoseState` (C→S).
- **Validação no servidor**: **Sim**. Valida `state` contra `Poses.Valid`, `pitch` numérico sem `NaN` (clamp em `[-1.3, 1.3]`), `side` em `{1, -1}` e aplica rate limit token bucket (`30 req/s` por jogador). Falta apenas log de abuso e uso do wrapper central de remotes.

### `ServerScriptService.Destruction.DestructionServer`
- **Tipo / Linhas**: `Script` (`Enabled=true`, `RunContext=Legacy`) · 59 linhas (sem `--!strict`)
- **O que faz**: Conecta `Touched` em todas as peças com tags `BreakableGlass` e `BreakableDoor` (`Size.Magnitude >= 3`) para quebrar por impacto de personagem ou veículo em alta velocidade. Quando `RunService:IsStudio()`, cria `ReplicatedStorage.Destruction.DevBreakRequest` e entrega a ferramenta `DestructionTester` aos jogadores.
- **Remotes**: Cria e recebe `Destruction.DevBreakRequest` (C→S, somente Studio).
- **Validação no servidor**: **Parcial**. `DevBreakRequest` valida tipo (`BasePart`, `Vector3`) e distância (`<= 200` studs da `Head`), mas sem checagem de `NaN` nem rate limit (mitigado pelo guard `IsStudio()`). Em `onTouched`, confia na `AssemblyLinearVelocity` de peças controladas pelo cliente (personagem/veículo).

### `ServerScriptService.Destruction.DestructionService`
- **Tipo / Linhas**: `ModuleScript` · 170 linhas (sem `--!strict`)
- **O que faz**: API de servidor (`Damage`, `Break`, `Restore`, `Explode`, `Resolve`, `GetType`, `IsBroken`, `BrokenSignal`) para quebrar objetos tagueados (`Destructible`, `BreakableGlass`, `BreakableDoor`), esconder/apagar luzes e restaurar após `RespawnTime` (usando `GetPartBoundsInBox` para não prender personagens).
- **Remotes**: Envia `Destruction.FXEvent` (S→C via `FireAllClients`).
- **Validação no servidor**: **Sim (API interna do servidor)**. Atenção: envia `FireAllClients` sem filtro de distância (desperdício de rede/CPU em mobile e incompatível com peças fora do raio de streaming).

### `ServerScriptService.Destruction.DestructionServer.DestructionTester.TesterClient`
- **Tipo / Linhas**: `LocalScript` (`Enabled=true`, `RunContext=Legacy`) · 10 linhas (sem `--!strict`)
- **O que faz**: Ferramenta de debug (distribuída só no Studio) que envia `mouse.Target` e `mouse.Hit.Position` para `DevBreakRequest` ao clicar.
- **Remotes**: Envia `Destruction.DevBreakRequest` (C→S).
- **Validação no servidor**: N/A (cliente; validado parcialmente em `DestructionServer`).

### `ServerStorage.__BlockoutLib`
- **Tipo / Linhas**: `ModuleScript` · 819 linhas (sem `--!strict`)
- **O que faz**: Biblioteca de construção procedural usada em Edit mode para gerar `District_Blockout` (prédios com paredes, aberturas, escadas, parapeitos, fachadas sólidas, escadas de incêndio, carros, palmeiras, postes, coberturas, mobília, prateleiras e tags de destruição). Não é requerida por nenhum script de runtime.
- **Remotes**: Nenhum.
- **Validação no servidor**: N/A (ferramenta de edição).

### `StarterPlayer.StarterCharacterScripts.MovementClient`
- **Tipo / Linhas**: `LocalScript` (`Enabled=true`, `RunContext=Legacy`) · 205 linhas (`--!strict`)
- **O que faz**: Implementa corrida (`Shift`), slide direcionável com `LinearVelocity` (`C`/`Ctrl`), shift-lock custom (`Alt`), troca de ombro (`X`/`R3`), offset de câmera de ombro/slide e rotação do torso para a câmera ao mirar/atirar. Expõe botões touch para Correr e Slide via `ContextActionService` e sincroniza estado local por atributos (`Sprinting`, `Sliding`, `Aiming`, `Firing`, `ShiftLock`, `ShoulderSide`).
- **Remotes**: Nenhum (estado de pose é lido e replicado por `PoseAnimator`).
- **Validação no servidor**: **Nenhuma** (movimento puramente client-side, ainda sem detecção server-side de speedhack/teleporte).

### `StarterPlayer.StarterPlayerScripts.GunClient`
- **Tipo / Linhas**: `LocalScript` (`Enabled=true`, `RunContext=Legacy`) · 351 linhas (`--!strict`)
- **O que faz**: Gerencia equipar/desequipar armas, disparo automático, previsão local (raycast, tracer Neon, spark, muzzle flash e som), coice de câmera, zoom de FOV ao mirar (`M2`/`L2`), recarga (`R`/`X` + botões touch), crosshair no mouse, HUD de munição e hitmarker animado (branco/amarelo headshot/vermelho kill).
- **Remotes**: Envia `Remotes.GunFire` (C→S) e `Remotes.GunReload` (C→S); recebe `Remotes.GunFX` (S→C) e `Remotes.GunHit` (S→C).
- **Validação no servidor**: N/A (cliente; dano e munição são decididos por `GunServer`).

### `StarterPlayer.StarterPlayerScripts.PoseAnimator`
- **Tipo / Linhas**: `LocalScript` (`Enabled=true`, `RunContext=Legacy`) · 247 linhas (`--!strict`)
- **O que faz**: Roda em `RunService.Stepped` para sobrescrever `Motor6D`s (ombros, quadris, pescoço, `RootJoint`) e `RightGrip` de **todos** os personagens R6 com base na pose da arma e no slide, espelhando automaticamente quando o jogador troca de ombro. Envia `PoseState` ao servidor em até 15 Hz com filtro de delta.
- **Remotes**: Envia `Remotes.PoseState` (C→S).
- **Validação no servidor**: N/A (cliente; validado por `PoseServer`).

### `StarterPlayer.StarterPlayerScripts.DestructionFX`
- **Tipo / Linhas**: `LocalScript` (`Enabled=true`, `RunContext=Legacy`) · 186 linhas (sem `--!strict`)
- **O que faz**: Ouve `Destruction.FXEvent` e cria no cliente fragmentos físicos (`shatter`/`chunks`/`fling` em `Workspace.LocalDebris`), partículas (`glint`, `dust`, `splinters`, `sparks`, `smoke`), flash de luz e áudio 3D (`RollOffMaxDistance=180`), respeitando `MaxDebris=120`.
- **Remotes**: Recebe `Destruction.FXEvent` (S→C).
- **Validação no servidor**: N/A (cliente).

---

## 3. Avaliação contra `AGENTS.md` e `docs/design.md`

### O que dá para aproveitar na Fase 0 (combate)
- **Base de gunplay já autoritativa e em `--!strict`**: `Weapons.Config`, `GunServer`, `GunClient`, `MovementClient`, `Weapons.Poses`, `PoseServer` e `PoseAnimator` já respeitam a regra nº 1 ("cliente nunca decide dano"), usam `--!strict` e `task.*`, e já entregam um loop básico de tiro + ADS + troca de ombro + corrida + slide + hitmarker + poses procedurais replicadas.
- **Assets prontos para acelerar o playtest da Fase 0**:
  - `StarterPack.M4A1` (modelo 3D funcional com `Muzzle`/`Flash`) serve como 1ª das 3 armas da Fase 0.
  - `TestDummy` (R6) serve para validação rápida de dano/headshot.
  - `District_Blockout` (especialmente uma quadra como `Q4_Center` ou `Q1_Northwest`, já com 93 coberturas marcadas `Cover=Low/Medium/High`) pode servir como arena urbana imediata de playtest da Fase 0, além de já alinhar com os roubos da Fase 1 (`ConvenienceStore`, `JewelryStore`, `Bank`, `ElectronicsStore`, `Garage_Hideout`).
- **Infraestrutura compatível**: `StreamingEnabled = true` já ativo.

### O que conflita com `AGENTS.md` / `docs/design.md`
1. **Estrutura fora do padrão Rojo / Services / Controllers**: os scripts atuais são `Script`/`LocalScript` soltos em serviços distintos, sem bootstrap `Init()`/`Start()` em `src/server/Services`, `src/client/Controllers` e `src/shared/{Lib,Config}`.
2. **Remotes pré-criados no Studio e sem wrapper único**: `ReplicatedStorage.Remotes` existe como pasta manual no Studio, sem módulo `shared/Lib/Remotes` com rate limit padronizado e log de abuso. `GunReload` não tem rate limit/log.
3. **Números de balanceamento hardcoded no código**: velocidades/slide/câmera em `MovementClient`, `SHOULDER_PEEK` e tolerância de cadência em `GunServer`, hold/coice/sons em `GunClient`, parâmetros de slide/transição em `PoseAnimator`. Regra do `AGENTS.md`: todo valor de balanceamento vai em `src/shared/Config`.
4. **Regra de facção errada em `GunServer.isEnemy`**: atualmente `Neutral` pode atacar e sofrer dano (`attacker.Neutral or victim.Neutral -> true`). No `design.md`, **Civil (neutro) não ataca nem pode ser atacado**, e **bandidos se atacam entre si** (sem equipe única imune entre bandidos).
5. **Lacunas obrigatórias da Fase 0 no combate**:
   - **Servidor (`GunServer`)**: falta lag compensation (buffer de posições ~1s + rewind limitado), dano por região completa (cabeça/tronco/membros) + queda por distância, camada de armadura (colete/capacete), estado **derrubado (`downed`)** com sangramento/reviver/finalizar, e logs anti-exploit de tiro impossível. Payload do tiro ainda manda só `target: Vector3` em vez de `{origem, direção, timestamp, arma}`.
   - **Cliente (`GunClient`)**: recoil horizontal é aleatório (`math.random`) em vez de **padrão aprendível** (design: spread aleatório só no hip fire); faltam kill feed, impacto de câmera, feedback diferenciado de armadura e camadas de áudio (perto/longe/eco).
   - **Movimento (`MovementClient`)**: faltam **mantle/vault, agachar, deitar (prone) e lean nas quinas**.
   - **Rig R6 acoplado (`PoseAnimator` / `Poses`)**: funciona apenas em R6 (`Torso`, `Right Shoulder`). Precisa alinhar com P3/P4 se o jogo final será R6 ou R15 (especialmente por causa das roupas 3D com bones e decisão de câmera 1ª/3ª pessoa em aberto).
6. **Meta de desempenho mobile (LOD)**:
   - `GunServer` envia `GunFX` para todos os jogadores sem filtro de distância, e `GunClient` instancia `Part`/`Sound` por bala sem pooling ou culling.
   - `PoseAnimator` calcula cinemática de braços/pernas em `Stepped` para todos os jogadores sem LOD de distância.
   - `District_Blockout` tem 12.516 descendentes e 159 luzes (`PointLight`/`SpotLight`/`SurfaceLight`); requer teste de FPS em emulador mobile e eventual simplificação pela P3.

### O que é de outro escopo (fora da Fase 0)
- **Sistema de Destruição (`Destruction/*`, `DestructionFX`, `DestructionTester`)**: fora das tarefas da Fase 0 (`docs/fases/fase-0.md`). Não usa `--!strict`, tem ferramenta de debug no `ServerScriptService`, usa `FireAllClients` sem LOD (spawnando até 28 peças físicas de vidro no cliente a qualquer distância), cria 259 conexões `.Touched` no servidor e nem está conectado ao `GunServer`.
- **Cidade inteira (`District_Blockout`) e `ProductTemplates`**: pertencem ao escopo de mapa/roubos da Fase 1+ (P3/P4), ainda que úteis como arena de teste temporária.
- **`__BlockoutLib`**: script auxiliar de edição, não faz parte do jogo em runtime.
- **Peças/Unions soltas em `Workspace`**: sobras de protótipo sem uso.

---

## 4. Recomendação por item

| Item no Studio | Ação | Destino / Observação |
|---|---|---|
| `ReplicatedStorage.Weapons.Config` | **Migrar para `src/`** | `src/shared/Config/Weapons.luau` — expandir com padrão de recoil, queda por distância, dano por região (cabeça/tronco/membros), armadura e mais armas da Fase 0. |
| `ReplicatedStorage.Weapons.Poses` | **Migrar para `src/`** | `src/shared/Config/WeaponPoses.luau` (se o time confirmar R6 + 3ª pessoa na Fase 0; senão, substituir por animações de P4). |
| `ServerScriptService.GunServer` | **Migrar e evoluir em `src/`** | `src/server/Services/CombatService.luau` (contrato `Init`/`Start`), usando `shared/Lib/Remotes`, lag compensation, regiões de dano, armadura, estado derrubado, regra correta de Civil/Bandido e logs anti-exploit. |
| `ServerScriptService.PoseServer` | **Migrar para `src/`** | `src/server/Services/PoseService.luau` (ou incorporar ao serviço de replicação de combate/movimento), usando `shared/Lib/Remotes` + `RateLimit`. |
| `StarterPlayerScripts.GunClient` | **Migrar e dividir em `src/`** | `src/client/Controllers/WeaponController.luau` + `HudController.luau` (HUD, hitmarker, kill feed), movendo números/sons para `shared/Config` e adicionando recoil aprendível e LOD nos tracers/FX. |
| `StarterCharacterScripts.MovementClient` | **Migrar para `src/`** | `src/client/Controllers/MovementController.luau` (ouvindo `CharacterAdded`, evitando depender de `StarterCharacterScripts`), movendo velocidades/slide para `src/shared/Config/Movement.luau` e adicionando mantle, agachar, deitar e lean. |
| `StarterPlayerScripts.PoseAnimator` | **Migrar para `src/`** | `src/client/Controllers/PoseController.luau` com culling/LOD por distância para mobile (enquanto R6 estiver ativo). |
| `ReplicatedStorage.Remotes` (pasta + 5 remotes) | **Descartar (após migração)** | Passam a ser criados dinamicamente no servidor pelo `src/shared/Lib/Remotes.luau`. |
| `ReplicatedStorage.Destruction.*`, `ServerScriptService.Destruction.*`, `StarterPlayerScripts.DestructionFX` | **Manter desativado no Studio (ou congelar para Fase 1+)** | Fora do escopo da Fase 0. Desabilitar `DestructionServer` e `DestructionFX` durante a Fase 0 para não interferir no playtest nem injetar `DestructionTester`. Quando reativar no futuro, migrar para `src/` em `--!strict` com LOD por distância. |
| `DestructionTester` / `TesterClient` | **Descartar** | Ferramenta de debug temporária que polui o inventário em todo Playtest no Studio. |
| `StarterPack.M4A1` | **Manter no Studio (mover de pasta na migração)** | Aproveitar o modelo 3D (P3); mover para pasta de assets (ex.: `ReplicatedStorage/Assets/Weapons` ou `ServerStorage`) quando o servidor passar a entregar armas por inventário/loadout em vez de `StarterPack`. |
| `Workspace.District_Blockout` | **Manter no Studio** | Asset de mapa da P3/P4; usar uma quadra como arena de teste na Fase 0 e revisar contagem de luzes/peças para celular médio. |
| `Workspace.TestDummy` | **Manter no Studio** | Útil para testes unitários/manuais de tiro e headshot na Fase 0. |
| `Workspace` (`5 Part`, `6 UnionOperation` soltos em `(-15, y, -41)`) | **Descartar** | Sobras de protótipo fora de pasta e sem uso. |
| `Lighting` + `MaterialService.AssistantMaterials` | **Manter no Studio** | Necessários para a aparência do `District_Blockout` (revisar efeitos de pós-processamento no teste mobile). |
| `ServerStorage.ProductTemplates` | **Manter no Studio** | Meshes de produtos de loja reutilizáveis pela P3 na Fase 1 (roubos tier 1). |
| `ServerStorage.__BlockoutLib` | **Manter no Studio (ou arquivar fora do place)** | Utilitário de geração em Edit mode; não afeta runtime, mas não deve ir para `src/`. |

---

## 5. Riscos de ligar o Rojo nesse place

### O que o Rojo vai gerenciar / sobrescrever
Com o `default.project.json` previsto no plano:
- `src/shared` → `ReplicatedStorage.Shared` (**não existe hoje** no place — nada será sobrescrito).
- `src/server` → `ServerScriptService.Server` (**não existe hoje** no place — nada será sobrescrito).
- `src/client` → `StarterPlayer.StarterPlayerScripts.Client` (**não existe hoje** no place — nada será sobrescrito).
- `Workspace.$properties.StreamingEnabled = true` (**já é `true`** no place — sem alteração).

### Riscos reais ao conectar o Rojo e como evitar
1. **Execução duplicada (risco principal)**: o Rojo preserva instâncias irmãs desconhecidas nos serviços raiz. Portanto, os scripts legados (`GunServer`, `PoseServer`, `GunClient`, `MovementClient`, `PoseAnimator`, `DestructionServer`, `DestructionFX`) **continuarão rodando junto com os novos Services/Controllers** sincronizados pelo Rojo.
   - *Sintoma*: dois tiros por clique, conflito de `ContextActionService` (`ShiftLock`, `Sprint`, `Slide`, `GunAim`, `GunReload`), dois `GunHUD`s, briga por `CameraOffset`/`FieldOfView`/`WalkSpeed`/`Motor6D` e colisão de atributos (`Ammo`, `Reloading`, `Aiming`, `Firing`, `Pose`).
   - *Mitigação*: antes de testar qualquer sistema migrado em `src/`, desabilitar (`Enabled = false`) ou remover os scripts legados correspondentes e a pasta manual `ReplicatedStorage.Remotes`.
2. **Interferência do `DestructionServer` no Studio**: enquanto `DestructionServer` estiver habilitado, ele injeta a tool `DestructionTester` na mochila de todo jogador em Playtest e cria `DevBreakRequest`. Desabilitar `DestructionServer` e `DestructionFX` durante a Fase 0 evita ruído nos testes de combate e de desempenho.
3. **`StarterPack.M4A1` equipada automaticamente**: ao migrar o sistema de armas para `src/`, a `Tool` em `StarterPack` continuará sendo entregue com atributos antigos (`Weapon`, `Ammo=30`, `Reloading=false`). Coordenar a troca para que apenas o novo `WeaponController`/`CombatService` controle a arma.
4. **Risco de configuração errada no `default.project.json`**: nunca definir `"$ignoreUnknownInstances": false` diretamente sobre `Workspace`, `ReplicatedStorage`, `ServerScriptService` ou `StarterPlayerScripts` — isso apagaria `District_Blockout`, `M4A1`, `AssistantMaterials` e os demais assets do Studio.
5. **Backup preventivo**: antes da primeira conexão do plugin Rojo, salvar uma cópia local (`.rbxl`) do place **Ceilandia** como ponto de restauração.
