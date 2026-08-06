# Downloads e integridade

Os arquivos executáveis e pacotes compactados são publicados na área [Releases](https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases). Esta pasta mantém o inventário criptográfico e o histórico técnico.

## Versão candidata recomendada: 2.2.5

A 2.2.5 corrige os defeitos confirmados em Windows na 2.2.4:

- manifesto de ativação inválido no launcher Portable;
- geração do `SetupHost.exe` dentro do payload já validado;
- barra lateral do Setup com logo/textos corrompidos.

Arquivos esperados na release `v2.2.5`:

- `SQLBackupAndFTP-AutoRunner-Setup-v2.2.5.exe`
- `SQLBackupAndFTP-AutoRunner-v2.2.5-Portable.zip`
- `SQLBackupAndFTP-AutoRunner-v2.2.5-Source.zip`
- `SHA256SUMS.txt`

> [!IMPORTANT]
> A 2.2.5 permanece Release Candidate até passar pela homologação real descrita em [HOMOLOGACAO_2_2_5.md](../docs/HOMOLOGACAO_2_2_5.md).

## Histórico

| Versão | Situação |
|---|---|
| **2.2.5** | Candidata recomendada para homologação |
| 2.2.4 | Substituída pela 2.2.5 |
| 2.2.3 | Substituída pela 2.2.4 |
| 2.2.2 | Substituída pela 2.2.3 |
| 2.2.1 | Substituída pela 2.2.2 |
| 2.2.0 | Substituída pela 2.2.1 |
| 2.1.0 RC | Legada, não recomendada |

## SHA-256

| Versão | Setup SHA-256 | Portable SHA-256 | Source SHA-256 |
|---|---|---|---|
| **2.2.5** | `698181548F6F05201C109D62711179EAE549368145FD974E71391C6E718F360C` | `E333255945A27C87B03D844AACE68071381E839F1D403E4AD90B53CC9F7DBD07` | `3D6C52F107E6F1291AD26A462403F97260DF3C70540B40DA5693EC55278B41D3` |
| 2.2.1 | `25F32312E183C17FCDED46319E205C41DEAA693E15194BCA91EF3D96B772AD88` | `2C0AD207D074E0C64E85629B01485E3E8E06914762AA4B5BA138F60B25E761D9` | `F0DE23AF579770710DC428C40031D7F8BFF2B4FA92618DE89313D19A32F3FBEB` |
| 2.2.0 | `8DDCD0E319AD31DEE9F6A688BEBE03DC9326B5E8A156C016327DEB976623328A` | `17E90F2C95BACFD023EFE3576826F20C0724341677770AB3E95626273BE89E83` | `A504259F175EE6D70822AE0D8CCA8A4525EF160CB19E4A5944B82EEA3C898109` |
| 2.1.0 RC | Não disponível | `D576440692E19816A3FA76805B377C599B8DEFC49E6F4A047547D121C9700D9E` | Incluído no pacote legado |

O inventário em formato automatizável está em [SHA256SUMS.txt](SHA256SUMS.txt).
