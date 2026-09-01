# APF — AI Project Factory

APF é uma plataforma local-first para transformar intenção humana em trabalho de IA governado, persistente e explicável.

O repositório concluiu a fundação e iniciou a Slice 1 CLI. `apf init` e `apf status` já formam um fluxo executável e testado; `apf doctor` existe com escopo determinístico, mas a persistência/invalidação do fingerprint de capabilities (`T1.5`) e o recovery de runs (`T1.6`) ainda impedem declarar a slice aceita. O Studio continua deliberadamente adiado.

## Estado atual

- arquitetura baseline: Rust Core, CLI-first e Tauri/React após o fluxo central funcionar;
- memória: SQLite + WAL + FTS5, mantida fora do workspace gravável pelo agente;
- execução: ainda não implementada no runtime; Execution Broker e adapter Codex pertencem à Slice 2, e o adapter Claude à Slice 6;
- segurança inicial: `CONTROLLED`, com controles classificados pelo nível real de enforcement;
- interoperabilidade: MCP e A2A ficam nas bordas; APF-CP governa o fluxo interno;
- licença: MIT existente, ainda aguardando ratificação explícita antes da abertura a contribuições.
- Gate 0: parcial; `T0.8a` autoriza somente Core determinístico/read-only judgment, e provider writes continuam `DENY`.

Comece por [PROJECT.md](PROJECT.md) e pelo [índice da fundação](docs/foundation/README.md).

## Validação local

SQLite e Node.js oficiais são baixados para `.tools/` e não são versionados. As duas bibliotecas do validador usam versões e integridades fixadas em `scripts/schema-validator/package-lock.json`. Execute:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-foundation.ps1
```

O comando valida APF-CP e a evidência fechada do Gate 0 com casos positivos e negativos, mensagens persistidas no Brain, schema SQLite, FTS5, integridade, leases, journal append-only e restauração de backup sem instalar dependências globalmente.

## Slice 1 CLI

Rust `1.98.0` e LLVM-MinGW `20260826` são baixados em `.tools/`. Instalador, archive, executáveis C usados e árvore completa da toolchain Rust são verificados por SHA-256; os comandos restauram o ambiente da sessão chamadora e não alteram o `PATH` global. Para validar e compilar:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-cargo.ps1 -Task Check
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-cargo.ps1 -Task Test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-cargo.ps1 -Task Clippy
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-cargo.ps1 -Task Build
```

Ou execute a suíte parcial completa com `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-slice1.ps1`.

Use somente os wrappers em `scripts/` para executar Rust. O bootstrap remove os proxies Cargo/rustc do rustup e mantém somente `rustup.exe` no home auxiliar; recriar ou invocar proxies sem `RUSTUP_HOME` repo-local pode criar ou baixar estado em `%USERPROFILE%\.rustup`.

`Cargo.lock` fixa a resolução; o wrapper faz `fetch --locked` e executa build/test com `--frozen`. Isso sustenta repetição no host medido, não uma alegação de build offline desde cache vazio ou bit-reprodutível.

O executável fica em `.tmp/cargo-target/debug/apf.exe`. `init` cria o Brain em `%LOCALAPPDATA%\APF\projects\<slug>--<project-ref>\brain.db` por padrão, fora do workspace; `--brain` aceita somente caminho absoluto cujo diretório pai já exista.

```powershell
.\.tmp\cargo-target\debug\apf.exe doctor
.\.tmp\cargo-target\debug\apf.exe init
.\.tmp\cargo-target\debug\apf.exe status
```

`status` retorna exit code `2` quando o SHA-256 de `PROJECT.md` diverge do manifest, quando digest/revisão persistidos divergem ou quando identidade/workspace do Brain não correspondem ao projeto. `init` publica somente um Brain completo e nunca sobrescreve um destino existente.

## Aviso de segurança

APF ainda não oferece contenção forte de agentes. Um processo Codex ou Claude executado como o mesmo usuário pode ter acesso aos recursos desse usuário. A arquitetura distingue controles impostos pelo SO, impostos pelo provedor, verificados posteriormente e meramente consultivos; não trate `CONTROLLED` como sandbox.
