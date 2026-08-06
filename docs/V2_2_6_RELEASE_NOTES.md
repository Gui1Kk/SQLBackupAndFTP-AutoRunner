# SQLBackupAndFTP AutoRunner 2.2.6 RC

## Correção principal

A atualização sobre uma instalação anterior não copia mais recursivamente a pasta protegida. O diretório antigo é renomeado atomicamente no mesmo volume, usado como rollback e removido sem seguir junctions ou links simbólicos.

Erros de enumeração agora são reportados como falhas de inspeção, em vez de serem mascarados como junction.

## Portable

Falhas na compilação inicial do host gráfico passam a registrar:

```text
%TEMP%\SQLBackupAndFTPAuto\portable-host-build.log
```

A mensagem apresenta o código e o caminho do log.

## Hashes da candidata

```text
496CE31869E73EAFAFE4369719237DB2325607CB0A30F3B7BBB8A2BD143CAB34  SQLBackupAndFTP-AutoRunner-Setup-v2.2.6.exe
985EA2DB505ACFEB856B233F8E369E7802290669A2BAFC9EA6B4D4E57B550CBE  SQLBackupAndFTP-AutoRunner-v2.2.6-Portable.zip
5E4CF2B36AA223B11C978B7076417B527A4220016A1EA955A822A4F758B59F94  SQLBackupAndFTP-AutoRunner-v2.2.6-Source.zip
```

## Estado

Release Candidate. A promoção a estável exige validação no Windows x64 que revelou o erro, além de backup e restauração reais.
