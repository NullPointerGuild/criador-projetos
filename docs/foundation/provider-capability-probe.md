# Provider capability probe

`initial_observed_at: 2026-08-28`  
`updated_at: 2026-08-31`  
`platform: Windows x64 build 26200.9168`  
`status: Gate 0 parcial; nenhum provider write aprovado`

Este documento resume comportamento observado. Não é garantia geral: hash de binário, configuração, conta de execução, privilégio ou build do sistema invalida o claim correspondente. A projeção fechada e validável está na [capability matrix](../../evidence/gate0/capability-matrix.v1.json); decisões por escopo estão em [Security decisions](../../evidence/gate0/security-decisions.v1.json).

## Inventário fixado

| Provider | Binário | SHA-256 | Estado |
|---|---|---|---|
| Codex CLI | `0.151.0-alpha.7.2` | `24a37127b8298b7bf96ca9b1d51a63c0685d561d1596f052bec73f734ed524b5` | ativo |
| Codex CLI | `0.150.0-alpha.12.2` | `b6e693173c2d526bff8400481197fbeafbd9fdcec43ca3471c9dc5f57565eb55` | histórico |
| Claude Code | `2.1.251` | `8d1229a281281b98fd2dee72b3253a704be4fce4d45207200cd32a9bb5a6c909` | ativo |

Os probes de schema iniciais usaram `codex exec` e `claude -p`, sem tools mutáveis. O Codex emitiu JSONL e usage no evento terminal; o Claude retornou envelope JSON com `structured_output`, usage, modelo canônico e estimativa list-basis. Nos dois adapters, o Core — não o modelo — MUST construir IDs, envelope e usage canônicos.

## Structured output e custo

O primeiro probe Codex enviou o envelope canônico inteiro como `--output-schema` e recebeu `invalid_json_schema`: no subset observado, propriedades declaradas precisavam constar em `required`, com opcionais representados por `null`. A projeção provider-facing revisada terminou com exit `0`. Erro de schema é falha de adapter/configuração, não logic retry do modelo.

No Claude, o validador do CLI não resolveu a metadata Draft 2020-12; `$schema` e `$id` foram removidos somente da projeção provider-facing. JSON deve ser passado como argv estruturado pelo adapter, sem shell intermediário. A projeção final, já sem `usage`, ainda não foi reexecutada em ambos os CLIs; `T0.2` e `T0.3` permanecem parciais.

Custos reportados pelo Claude Code são estimativas `LIST`, nunca gasto `ACTUAL`:

| Escopo | Estimativa reportada |
|---|---:|
| sessões diretas desta retomada, antes do HTTP 429 | US$ 5.8095745 |
| acumulado anterior registrado no handoff | US$ 10.6540770 |
| acumulado direto do projeto após esta retomada | US$ 16.4636515 |

O run final recebeu HTTP `429`, não produziu output e reportou custo zero. O custo real da assinatura/cobrança continua `UNKNOWN`; não há ledger financeiro verificado.

## Isolamento de instruções

`--ignore-rules` ignora arquivos de execpolicy `.rules`; não desativa `AGENTS.md`. `--ignore-user-config` ignora `config.toml`, incluindo o backend Windows, se não for reposto explicitamente. No Codex histórico `0.150.0-alpha.12.2`, `project_doc_max_bytes=0` suprimiu o canário de instrução, mas somente para aquele hash.

O autoload não foi reavaliado no binário ativo `0.151.0-alpha.7.2`. Portanto, `T0.9` é parcial e o claim ativo é `UNKNOWN`. O fato de o código-fonte explicar o downgrade quando falta configuração do sandbox aumenta a confiança da hipótese, mas não isola a causa do run histórico, no qual binário e configuração mudaram juntos.

## Permission mode do Codex

Evidência histórica `0.150.0-alpha.12.2`:

- read-only interno foi bloqueado;
- o controle positivo workspace-write interno falhou;
- a rejeição externa não prova containment porque o controle positivo falhou;
- classificação preservada: `UNKNOWN_OR_FAILED` / controle inválido.

Evidência ativa `0.151.0-alpha.7.2`, hash fixado, `--ignore-user-config` e `windows.sandbox="elevated"` explícito:

- read-only interno: nenhuma escrita, expectativa satisfeita;
- workspace-write interno: escrita criada com conteúdo exato, expectativa satisfeita;
- workspace-write em arquivo irmão comum: nenhuma escrita, expectativa satisfeita;
- uma execução por caso, exit `0`, sem timeout.

O classificador bruto procurava somente evento de tool ou texto de rejeição e, por isso, não reconheceu a escrita bem-sucedida apesar do conteúdo exato no alvo. `DEF-01` preserva esse defeito e a evidência bruta; a regra foi corrigida no script, sem novo model call. A derivação fechada é `PROVIDER_ENFORCED_AS_PROBED`, confiança média. Ela não prova junction, hardlink, device path, symlink ou TOCTOU e não autoriza writes do executor.

## Controles do host não são controles do provider

Na fixture host-local:

- Job Object encerrou a árvore em `5/5` trials;
- env allowlist e redirecionamento de profiles esconderam canários em `5/5`;
- `2 MiB` por stream foram drenados e `32 KiB` retidos;
- sanitização do corpus de terminal passou;
- loopback continuou acessível;
- hardlink e junction foram detectados somente pós-efeito;
- TOCTOU escapou;
- symlink ficou `UNKNOWN` por privilégio indisponível.

Esses resultados validam mecanismos de Layer A contra a fixture, não sua transferência automática a Codex ou Claude. Egress público/DNS do provider real, crash recovery e efeito externo desconhecido não foram medidos.

## Status do Gate 0

| Item | Estado verificado |
|---|---|
| `T0.1` versões/help/descriptor | parcial |
| `T0.2` Codex structured output/error/usage | parcial; schema final sem re-probe |
| `T0.3` Claude schema/cost | parcial; schema final sem re-probe |
| `T0.4` cancel/process tree | parcial; fixture host passou, transferência ao provider desconhecida |
| `T0.5` env/secrets/output | parcial; fixture host passou, same-user stores fora do claim |
| `T0.6` paths | parcial; detecção pós-efeito, race escapou, symlink desconhecido |
| `T0.7` network | parcial; somente loopback medido |
| `T0.9` autoload | parcial; somente hash histórico medido |
| `T0.10` crash/recovery | não atendido |
| `T0.11` usage/cost | não atendido para executor; actual cost desconhecido |
| `T0.8` Gate geral | incompleto, grants mutáveis negados |
| `T0.8a` Slice 1 determinística | emitido com limites advisory e sem provider runtime |
| `T0.8b` provider writes | incompleto e negado |
| `T0.8c` conteúdo hostil | requer container/VM ainda não medido; execução recusada |

Fontes oficiais consultadas em `2026-08-31`: [Codex sandboxing](https://learn.chatgpt.com/docs/sandboxing), [non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode) e [Windows sandbox](https://learn.chatgpt.com/docs/windows/windows-sandbox). Limitação: documentação define semântica esperada; o nível de enforcement registrado decorre apenas dos mecanismos nomeados e medidos.
