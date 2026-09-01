# Decisão de arquitetura fundacional

`outcome: DECISION_WITH_DISSENT`  
`decision_owner: Central Orchestrator`  
`decided_at: 2026-08-28`  
`reversibility: expensive after production code; easy during current spikes`

## Correção do founding prompt

“Central Orchestrator” passa a designar uma responsabilidade, não um loop de controle residente em um modelo.

| Control plane determinístico | Judgment plane por modelos |
|---|---|
| estados, leases, dependências, budgets, grants, aprovações, retries, gates, journal | intake, planejamento, decomposição, implementação, revisão, classificação e síntese de `Ask Project` |
| testado sem tokens | avaliado por evals e evidência |
| independente de provider | roteado por adapter/capability |

Essa separação é obrigatória para retomada, enforcement, custo previsível e substituição de provider.

## Conselho

Participaram contextos separados para Research, Architecture/Devil's Advocate, Security/DX/FinOps e uma revisão externa Claude Opus 5/max. O resultado não foi votação:

- Stack Research sustentou Rust/Tauri/SQLite.
- O conselho FinOps/Devil's Advocate preferiu TypeScript/Electron pela velocidade.
- Security vetou qualquer autonomia geral enquanto subprocessos rodarem com autoridade do usuário.
- Claude recomendou Rust Core + CLI primeiro + Tauri depois e separação `Judge`/`Executor`.

Uma rodada substancial foi suficiente; novas rodadas sem experimento apenas repetiriam preferências.

## Opções reais

| Opção | Forma | Vantagem | Fraqueza |
|---|---|---|---|
| **A — Rust Core, CLI-first** | biblioteca Rust + CLI; Tauri/React na slice seguinte; SQLite/rusqlite; broker nativo | coerente com processo privilegiado, distribuição e APIs de SO; evita reescrita do Core | aprendizado/iteração inicial e pré-requisitos Windows |
| **B — TypeScript, Electron depois** | Node/TypeScript para Core/CLI; Electron/React; SQLite Node | uma linguagem com UI e prototipagem rápida | runtime/main privilegiado, native modules/packaging e provável helper nativo para sandbox |
| **C — Isolation-first** | control plane + workers em container/VM/sandbox forte desde o início | alegações de segurança mais defensáveis para conteúdo hostil | instalação, matriz de SO e UX inviabilizam a prova mínima |

Tauri Studio-first também foi considerado e rejeitado por sequenciamento: renderer, WebView, IPC e installer não testam a hipótese central.

## Síntese

### `DEC-001` — Control plane determinístico

Aceita. Modelos nunca possuem o estado canônico do workflow nem concedem a si próprios permissões.

### `DEC-002` — Rust Core + CLI-first + Tauri posterior

Aceita com timebox. O workload de longo prazo — SQLite, supervisão de processos, secrets e backends de SO — favorece Rust. O Studio usa React/TypeScript, mas não entra no caminho crítico da primeira prova.

**Dissenso preservado:** TypeScript pode vencer se o bootstrap/Rust dominar o ciclo ou se a fluência real impedir entregas. Nesse caso, manter a mesma arquitetura lógica em TypeScript é melhor que um Core Rust paralisado.

### `DEC-003` — SQLite e artifacts fora do workspace

Aceita. A localização é resolvida por diretório de dados da aplicação/configuração, nunca por path pessoal hardcoded. `.apf/project.yaml` mantém identidade e intenção; exportação fornece portabilidade. O worker não recebe acesso de escrita ao Brain, backups ou artifacts canônicos.

### `DEC-004` — APF-CP como contrato local

Aceita. V1 é JSON tipado/persistido entre Core e worker, não rede, broker distribuído ou substituto de MCP/A2A.

### `DEC-005` — Segurança com níveis verificáveis

Aceita. Cada grant declara:

- `OS_ENFORCED` — kernel/container/VM testado;
- `PROVIDER_ENFORCED` — sandbox/permission do CLI, versionado e testado;
- `APF_VERIFIED` — checagem posterior, não prevenção;
- `ADVISORY` — instrução/política sem barreira técnica.

O termo `CONTROLLED` descreve governança humana, não isolamento.

### `DEC-006` — Providers em ordem de prova

Codex `exec` é o primeiro adapter por estar no `PATH`, ter documentação oficial de JSONL/schema e ser o Orchestrator configurado. Claude Code é o segundo adapter e deve passar a mesma suíte; a revisão fundacional já confirmou `claude-opus-5`/`max`, output JSON, uso/custo e modo restrito.

## Arquitetura baseline

```text
APF CLI (slice 1)          APF Studio/Tauri (slice 2)
          \                    /
           \ typed commands  /
            v               v
        +-------------------------+
        |        APF Core         |
        | deterministic workflow  |
        | policy + approvals      |
        | Project Brain API       |
        | query/explain           |
        +------------+------------+
                     |
             typed execution spec
                     v
        +-------------------------+
        |    Execution Broker     |
        | argv/env/cwd/limits     |
        | cancellation/audit      |
        | sandbox backend         |
        +------------+------------+
                     |
              Provider Adapter
                     v
              Codex / Claude CLI
```

Conceitos de módulos, sem criar estrutura vazia:

- `apf-domain`: entidades, estados e invariantes;
- `apf-brain`: migrations, repositories, FTS e backup;
- `apf-runtime`: scheduler sequencial, leases, approvals e recovery;
- `apf-providers`: capability descriptors, `Judge` e `Executor`;
- `apf-security`: policy evaluation e sandbox backends;
- `apf-git`: worktrees, diff, scope verification e gates;
- `apf-cli`: entrada inicial;
- `apf-studio`: cliente Tauri posterior, IPC estreito.

`Judge` e `Executor` são responsabilidades separadas mesmo quando usam o mesmo provider. `Judge` não possui side effects; `Executor` recebe workspace e grants delimitados.

## Processo e persistência

- Um writer lógico por Brain.
- Uma execução ativa por projeto.
- Sem daemon obrigatório; o processo CLI/Studio recupera leases expirados no startup.
- Sem retry automático após efeito externo desconhecido.
- Git é fonte do código; Brain é fonte de decisões/execução; `PROJECT.md` é contrato humano; secret store guarda credenciais.
- O renderer futuro não recebe shell/filesystem genérico; expõe comandos como `start_run`, `cancel_run` e `approve_capability`.

## Interoperabilidade

- **MCP:** tools/context externos, adapter versionado; não é Brain nem scheduler.
- **A2A:** agentes remotos, somente quando existir peer real; mapeamento no edge.
- **Skills/plugins:** formatos nativos preservados; importação/validação local depois da prova; sem marketplace V1.
- **Provider CLI:** interface fina e capability discovery por versão; app-server experimental fica adiado.

## Revisit triggers

| Atual | Reavaliar quando | Próximo candidato |
|---|---|---|
| Rust Core | bootstrap/fluência impedir uma fatia dentro do timebox | TypeScript modular, mesma API/Brain |
| CLI sem daemon | trabalho precisar continuar sem cliente ou concorrência >1 | daemon local atrás da API existente |
| Tauri | WebView, PTY, acessibilidade ou packaging falhar em spike | Electron shell mantendo Core/broker Rust |
| SQLite single writer | multi-machine ou writers concorrentes reais | reavaliar banco; não presumir PostgreSQL |
| SQL + FTS5 | recall falhar no eval fixo | índice semântico local auxiliar |
| `SHAPED` + `VERIFIED` | primeiro repo não confiável ou write fora do escopo | container/VM obrigatório |
| APF-CP local | segundo host ou agente externo real | transporte de rede e adapter A2A |

## Autocrítica aplicada

| Risco da proposta | Correção |
|---|---|
| overengineering | Studio, daemon, plugins, A2A, vetores e paralelismo removidos da slice 1 |
| abstração prematura | somente interfaces `Judge`, `Executor`, Brain e policy têm dois consumidores/casos claros |
| segurança fraca | claims por nível; veto a autonomia; Brain fora do workspace |
| cross-platform | Windows validado primeiro; nenhum selo genérico |
| token waste | controle sem modelo, contexto por refs/hash, progresso por evento de processo |
| provider lock-in | contrato canônico + capability descriptors + segunda suíte Claude |
| UX ruim | CLI é experimento, não destino; Studio de três jornadas entra logo após prova |
| viabilidade econômica | um provider e uma execução; medir overhead versus uso direto |
| manutenção | modular monolith e single process; sem infraestrutura distribuída |

## Licença

O arquivo MIT existente permanece intacto. A recomendação do conselho é Apache-2.0 por permissividade com grant explícito de patentes, mas trocar uma licença é decisão legal/humana. `ATTN-001` deve ser resolvido antes de contribuições externas; este documento não é aconselhamento jurídico.
