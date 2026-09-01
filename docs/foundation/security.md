# Security model V1

Status: threat model aprovado; Gate 0 permanece parcial. `T0.8a` permite somente a Slice 1 determinística e judgment de desenvolvimento estritamente read-only com limites advisory; `T0.8` e `T0.8b` seguem incompletos, e writes de provider continuam negados.  
Decision owner: Security role, com veto sobre autonomia geral.

## Verdade central

Um Codex/Claude CLI executado como o mesmo usuário herda, por padrão, a autoridade desse usuário. Um broker em user space não intercepta syscalls feitos diretamente pelo child process. Portanto:

- policy e prompt não são sandbox;
- worktree limita coordenação Git, não acesso ao filesystem;
- Job Object limita recursos/process tree, não paths ou rede;
- verificação de diff detecta parte dos efeitos depois, não previne efeitos fora do repo;
- “allow somente domínio X” exige proxy/namespace/VM equivalente; não é uma flag portátil.

V1 oferece governança controlada e controles honestamente classificados. Repositórios não confiáveis MUST ser recusados enquanto containment real não estiver ativo.

## Trust boundaries

| Classe | Componentes | Tratamento |
|---|---|---|
| confiável | APF Core first-party, migrations assinadas/revisadas, policy evaluator | mínimo privilégio e atualização controlada |
| privilegiado | Execution Broker e backend de sandbox | pequeno, auditável, sem renderer code |
| protegido | Brain, backups, artifact store, secret store | fora do workspace e nunca exposto ao model |
| não confiável | repo, `AGENTS.md`, `CLAUDE.md`, hooks Git, scripts, web, issues, artifacts e provider output | dados sem autoridade de instrução |
| extensão não confiável | skills, plugins, MCP servers e A2A peers | deny por padrão, revisão e grants separados |
| externo | OpenAI/Anthropic e outros providers | disclosure de destino, termos, retenção e capability |
| humano privilegiado | owner local | pode sobrescrever; override é registrado, não chamado consenso |

## Enforcement vocabulary

| Nível | Significado | Pode sustentar promessa preventiva? |
|---|---|---|
| `OS_ENFORCED` | kernel, container ou VM testado impede a ação | sim, dentro dos limites medidos |
| `PROVIDER_ENFORCED` | versão testada do provider bloqueia a ação | somente com caveat de dependência do provider |
| `APF_VERIFIED` | APF verifica efeito depois (diff/hash/log) | não |
| `ADVISORY` | prompt, policy visual ou convenção | não |

UI, audit e APF-CP MUST usar estes nomes. `UNKNOWN` bloqueia a elevação em vez de ser convertido em `ALLOW`.

## Threat model

| ID | Ameaça | Cenário | Controle V1 | Residual / gate |
|---|---|---|---|---|
| `THR-001` | repositório malicioso | instruções, config, hook ou build script tenta assumir autoridade | conteúdo marcado untrusted; hash/review de arquivos de instrução; hooks não executados; build gates em worker | no Codex medido, `--ignore-rules` não desativa `AGENTS.md`; `project_doc_max_bytes=0` suprimiu o canário somente na versão/hash testada |
| `THR-002` | prompt injection | web/doc/output solicita secret, grant ou mudança de policy | hierarchy fixa; model não chama policy API; external actions negadas | model pode produzir payload malicioso; Core valida schema e grants |
| `THR-003` | skill/plugin malicioso | hook/script ganha shell/network/credential | plugins fora da V1; import local requer source/license/permission review | supply chain permanece risco após habilitação |
| `THR-004` | filesystem escape | `..`, symlink, junction, hardlink ou TOCTOU sai do workspace | paths relativos fechados, inspeção handle-aware e pós-diff | hardlink/junction foram detectados somente após a possibilidade de escrita; TOCTOU escapou e symlink ficou `UNKNOWN`; prevention same-user é `ADVISORY` |
| `THR-005` | secret exposure | env, config, credential helper ou log entrega credencial ao child/model | env allowlist; Git credentials neutralizadas; secret refs; redaction; Brain sem secrets | provider autenticado pode manter credenciais próprias; disclosure explícito |
| `THR-006` | shell injection | campo de projeto vira command line | executable + argv; `shell=false`; cwd validado; nenhuma concatenação | scripts de package/build continuam código não confiável |
| `THR-007` | network exfiltration | child abre conexão arbitrária/DNS tunnel | network deny onde provider/OS provar; sem domínio allowlist fictícia | em CLI same-user pode ser apenas provider-enforced/advisory |
| `THR-008` | provider compromise | binário/update/provider remoto retorna ou executa ação hostil | versão/hash, assinatura quando disponível, auto-update controlado, grants mínimos | provider-native sandbox não é controle independente |
| `THR-009` | ação destrutiva | delete, force push, migration ou produção | classes separadas; preview/approval; remote Git pelo Core; produção/finance deny | approval humana não torna payload seguro |
| `THR-010` | privilege escalation | child herda token elevado, handle, service ou helper | Core não roda elevado; handle inheritance off; helper mínimo; no generic IPC | backends OS-specific ainda precisam de hardening |
| `THR-011` | supply chain | package, Tauri plugin, crate ou binary comprometido | locks, checksums, provenance/SBOM/scans em release, dependências mínimas | first build ainda baixa código; CI isolada necessária |
| `THR-012` | resource exhaustion | fork bomb, output flood, disco, CPU, tokens | timeout, byte cap, concurrency 1, Job Object/cgroups, budget states | Windows Job Objects não controlam rede/filesystem |
| `THR-013` | replay/duplicação | retry repete deploy/mensagem/compra | idempotency + receipt; unknown effect bloqueia retry | CLI opaco pode esconder efeito externo |
| `THR-014` | Brain tampering/corruption | agent/user altera histórico ou migration falha | fora do workspace, single writer, append-only triggers, backup+restore | não é tamper-proof contra owner/admin |
| `THR-015` | Studio XSS/IPC | artifact/Markdown injeta script e chama backend | CSP, sanitização, sem remote content, Tauri commands estreitos | previews complexos ficam desativados inicialmente |

## Execution Broker

O Broker é o único componente APF autorizado a criar subprocessos. Antes do spawn, MUST:

1. resolver executable absoluto e registrar versão/hash quando disponível;
2. construir argv como lista, nunca shell string;
3. validar/canonicalizar workspace e scope contra handles/reparse points;
4. montar environment por allowlist, sem copiar `*_TOKEN`, `*_KEY`, `*_SECRET`, cloud vars ou credential helpers;
5. definir cwd, stdin mode, stdout/stderr byte caps, timeout e cancel policy;
6. aplicar backend OS/provider e registrar o nível real;
7. desabilitar Git remote operations no child; pushes são ação brokered separada;
8. capturar process tree e matar descendentes no cancel/timeout;
9. após saída, recalcular Git diff, hashes e protected paths;
10. normalizar resultado sem confiar no texto “done”.

Em CLI mode, tools internas do provider podem escapar de brokers APF. Um futuro **brokered mode** desabilita shell/filesystem nativos do provider e oferece apenas tools APF. Isso medeia pedidos feitos pelo modelo, mas não confina syscalls de um CLI comprometido; prevenção contra o próprio provider ainda exige mecanismo independente de SO/container/VM e validação.

## Sandboxes por plataforma

| Plataforma | Baseline de prova | Containment candidato | Limite |
|---|---|---|---|
| Windows | Job Object + env scrub + output caps + diff medidos em fixture host-local; provider sandbox separado por binário/config | sandbox nativo elevado do provider para repo do owner; VM/Windows Sandbox para hostil | Layer A não transfere automaticamente ao provider; Job Object não confina paths/rede; positive control writable é obrigatório |
| macOS | process group + env + diff | App Sandbox/XPC para helper assinado; VM para hostil | CLI arbitrário e grants dinâmicos são difíceis; validar assinatura/entitlements |
| Linux | process group + env + diff | Landlock + bubblewrap/seccomp/cgroup | depende de kernel/user namespaces; allowlist por hostname exige proxy |

O experimental `CreateProcessInSandbox` do Windows não é baseline. Docker não é requisito para uso normal. Container/VM se torna obrigatório para conteúdo explicitamente não confiável até existir alternativa equivalente testada.

## Secrets

- Project Brain guarda `credential_ref`, nunca material.
- Preferir Windows Credential Manager, macOS Keychain e Linux Secret Service.
- Quando possível, o broker executa ação autenticada sem entregar secret ao model/child.
- Logs e argv recebem redaction antes de persistência.
- Auth state de Codex/Claude não é copiado, exportado ou incluído em context packs.
- Secret encontrado no output gera incidente e bloqueia commit/artifact até rotação/revisão.

## Network e privacy

Antes de cada envio, a UI/CLI mostra provider, destino, classe de dados, arquivos/context refs e enforcement de rede. Local-first não significa que inferência é local.

V1:

- `production`, `financial_spending`, `external_communication`, `secrets` e `cloud`: `DENY`;
- `destructive_action`: no máximo `ASK`; `ALLOW` nunca usa enforcement `ADVISORY`;
- pesquisa web: task distinta, conteúdo untrusted e provenance obrigatório;
- network do executor: mínimo suportado pelo provider; qualquer ausência de prova é exibida;
- telemetry APF: off por padrão.

## Supply chain e updates

- fixar Rust toolchain/Cargo.lock e package lock;
- verificar SQLite/sidecars por checksum oficial;
- não executar install scripts de repo não confiável no host;
- Tauri updater futuro exige assinatura; auto-update de provider invalida capability descriptor;
- skills/plugins passam por inspeção de source, licença, scripts, dependencies, network, filesystem e secrets;
- release gera SBOM e executa dependency audit antes de assinatura.

## Gate 0 — “É controlável?”

Nenhuma implementação com writes autônomos avança sem fixtures benignas e adversariais que medem:

- structured output e exit codes;
- cancelamento e morte de netos;
- timeout/output/fork limits;
- env secret inheritance;
- `..`, symlink/junction/hardlink e TOCTOU;
- write fora de allowed/protected paths;
- network/egress real;
- provider-native permission modes;
- crash/restart e efeito desconhecido;
- uso/custo reportado;
- auto-loading de instructions/MCP/plugins.

Saída é uma capability matrix versionada por binário e plataforma. O Security role pode concluir:

- `APPROVED_CONTROLLED`;
- `APPROVED_WITH_ADVISORY_LIMITS`;
- `REQUIRES_CONTAINER`;
- `REJECTED`.

### Estado medido em 2026-08-31

- Layer A host-local: Job Object matou a árvore em 5/5; env scrub escondeu canários e redirecionou profiles em 5/5; `2 MiB` por stream foram drenados e `32 KiB` retidos; sanitização passou no corpus. Isso não prova transferência ao provider.
- Paths: detecção pós-efeito existe para hardlink/junction; TOCTOU escapou; symlink e prevention provider-native permanecem `UNKNOWN`.
- Network: loopback permaneceu alcançável. DNS/public egress do provider real não foram medidos; destination disclosure é obrigatório e não é containment.
- Autoload Codex `0.150.0-alpha.12.2`: `--ignore-rules` trata execpolicy, não `AGENTS.md`; `project_doc_max_bytes=0` suprimiu o canário. Mudança de hash invalida o claim.
- Permission mode Codex `0.150.0-alpha.12.2`: evidência histórica `UNKNOWN_OR_FAILED`; o controle positivo writable falhou e o resultado não foi reinterpretado. A ausência de configuração do backend Windows explica o downgrade no código-fonte da versão, mas a execução histórica também difere em binário e configuração; portanto, a causa específica daquele run permanece `INFERENCE`, não fato medido.
- Permission mode Codex `0.151.0-alpha.7.2`: com hash fixado e `windows.sandbox="elevated"` explícito, uma execução por caso satisfez as três expectativas: bloqueio read-only interno, escrita workspace-write interna com conteúdo exato e bloqueio de arquivo comum fora do workspace. A classificação bruta permaneceu `UNKNOWN_OR_FAILED` por `DEF-01`; o script foi corrigido sem alterar a evidência nem repetir o modelo. O claim derivado é `PROVIDER_ENFORCED_AS_PROBED`, confiança média, e não autoriza writes autônomos nem prova contenção adversarial.
- O estado do binário Codex ativo e as decisões por escopo estão na [capability matrix](../../evidence/gate0/capability-matrix.v1.json) e nas [decisões Security](../../evidence/gate0/security-decisions.v1.json). `UNKNOWN` sempre resulta em `DENY`.

Fontes oficiais consultadas em `2026-08-31`: [Codex sandboxing](https://learn.chatgpt.com/docs/sandboxing), [non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode) e [Windows sandbox](https://learn.chatgpt.com/docs/windows/windows-sandbox). Limitação: documentação descreve comportamento esperado; enforcement local só é alegado onde o mecanismo nomeado foi medido. Confiança alta para semântica documentada, condicionada a versão/configuração.

## Veto

Modo `AUTONOMOUS` geral, produção, comunicação externa, secrets, cloud e gasto financeiro permanecem indisponíveis até controle preventivo independente ser demonstrado e revisado. O humano pode aceitar risco em tarefa específica elegível; não pode superar hard veto nem transformar `ADVISORY` em `OS_ENFORCED` por override.
