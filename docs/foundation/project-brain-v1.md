# Project Brain V1

Produto/contrato: `V1`. Schema SQLite greenfield atual: `PRAGMA user_version = 2`.

Executable schema: [`spec/project-brain/v1/schema.sql`](../../spec/project-brain/v1/schema.sql)  
Seed: [`spec/project-brain/v1/seed.sql`](../../spec/project-brain/v1/seed.sql)

## Papel

Project Brain é a memória institucional canônica do projeto. Ele não substitui Git, não guarda secrets e não tenta persistir thinking privado. Mantém estado atual + journal append-only + relações suficientes para responder perguntas com referências internas.

## Localização e ownership

- O banco autoritativo fica no diretório de dados APF, fora do repositório/worktree entregue ao agente.
- O artifact store e backups ficam no mesmo domínio protegido, também fora do workspace.
- `.apf/project.yaml` guarda identidade, schema e hash do contrato humano; não contém credenciais.
- Somente a API do Core escreve. Studio, CLI e agentes não espalham SQL.
- Portabilidade é fornecida por exportação futura; não por tornar o banco gravável pelo executor.
- V1 mantém exatamente um projeto por arquivo de Brain (`projects.id = 1`) e limita autonomia persistida a `CONTROLLED | SHARED`.
- A publicação inicial e os backups usam arquivo de staging no mesmo diretório, validação completa e `hard_link` sem overwrite antes de remover o nome temporário.
- `status` só expõe conteúdo operacional depois de confirmar `project_ref`, slug e workspace canônico do vínculo persistido.

## Baseline SQLite

- SQLite 3.53.4 ou superior verificado no artefato final;
- `WAL`, local filesystem e um writer lógico;
- `synchronous=FULL` até benchmark/risco justificar mudança;
- `foreign_keys=ON`, `busy_timeout=5000`, transações curtas;
- FTS5 com `unicode61`, sem embeddings;
- limites de tamanho/SQL reduzidos no runtime quando entradas não confiáveis forem aceitas.

WAL permite readers com um writer; não permite múltiplos writers simultâneos nem uso seguro em filesystem de rede. Reads longos podem impedir checkpoint e devem ser observados.

## Estruturas V1

| Estrutura | Responsabilidade |
|---|---|
| `schema_migrations` | versão, checksum e momento de aplicação |
| `projects` | identidade, intent digest, propósito, modo e autonomia |
| `actors` | humanos, roles, agent instances, providers e sistema |
| `policy_snapshots` | policy ratificada, hash e ator ratificador; imutável por triggers |
| `tasks` / `task_dependencies` | estado, lease, aceitação e DAG |
| `work_orders` | APF-CP canônico, referência ao policy snapshot, context hash e idempotência |
| `runs` | lineage, provider/model, identidade de processo, commits, enforcement observado, mensagem `RESULT` canônica e projeção de usage |
| `knowledge_items` | goals, requirements, decisions, claims, evidence, assumptions, risks e research |
| `relations` | grafo relacional por referências canônicas |
| `approvals` | pedido, expiração, ator e resultado humano/policy |
| `artifacts` | metadata de conteúdo endereçado por SHA-256 |
| `cost_entries` | estimated/committed/actual com `cost_basis`, fonte e confiança |
| `attention_items` | orçamento de atenção humana |
| `audit_events` | journal operacional append-only |
| `brain_fts` | índice textual reconstruível, nunca fonte da verdade |

É mais que oito tabelas, mas cada uma atende uma consulta ou invariante V1 concreta. Não existem tabelas para organization units, plugins, lifecycle, metrics, experiments, pricing catalog, embeddings ou A2A. Um `work_order.policy_snapshot_id` referencia a linha imutável; o snapshot não vive apenas dentro do JSON da mensagem.

## IDs e relações

- PKs inteiras otimizam joins locais.
- `ref` humana (`DEC-0001`, `RUN-0001`) é única e citável.
- `relations` liga refs com vocabulário fechado: supports, contradicts, depends_on, implements, supersedes, produced_by, threatens, validates, owned_by, reviews e derived_from.
- O Core valida existência/tipo dos endpoints porque SQLite não pode criar uma FK polimórfica limpa.
- Decisões preservam alternativas, dissent e revisit trigger em `data_json`; promovê-los a tabelas próprias somente quando consultas reais exigirem.

## Journal

Triggers rejeitam `UPDATE`, `DELETE`, conflito por `INSERT OR REPLACE` e inserção backdated em `audit_events`. Correção é novo evento, nunca mutação histórica. O controle de backdating compara timestamps canônicos como texto; o Core MUST produzir RFC 3339 normalizado para que a ordenação seja válida.

Isso fornece auditabilidade, não não-repúdio. Um usuário local privilegiado ou uma migração que remova triggers pode alterar o arquivo. Assinatura/hash chain é adiada até existir ameaça ou requisito real.

O schema também rejeita segundo projeto no mesmo DB, autonomia fora de `CONTROLLED | SHARED`, mutação de policy snapshot, lease presente fora de `LEASED/EXECUTING`, identidade de processo parcial, `RUNNING` sem processo, enforcement observado fora do vocabulário fechado, combinações inconsistentes de `state/cost_basis`, hashes fora do formato e JSON com tipo estrutural errado. Validação APF-CP permanece no Core; o smoke test extrai as mensagens seed do banco e as valida pelo schema normativo.

## FTS e Ask Project

FTS é preenchido pela aplicação com texto selecionado; não usa triggers cruzando todas as tabelas. Pode ser reconstruído a partir dos registros canônicos.

Pipeline:

```text
pergunta
→ query plan determinístico
→ SQL + FTS5
→ records canônicos
→ síntese por Judge
→ verificação de cada ref citada
→ resposta ou UNKNOWN
```

Perguntas canônicas V1:

- o que mudou e em qual run?
- por que uma decisão foi tomada e quem dissentiu?
- qual evidência suporta/contradiz a decisão?
- quanto tempo/tokens/custo foram reportados, com qual `state`, `cost_basis`, fonte e confiança?
- qual task está bloqueada e qual ação é necessária?

Embeddings só entram se um eval fixo demonstrar falha material de recall do SQL/FTS.

## Migração, backup e recovery

1. verificar schema version e checksum;
2. checkpoint controlado quando seguro;
3. criar snapshot consistente pela Online Backup API ou `VACUUM INTO`;
4. aplicar migration forward-only dentro de transação quando suportado;
5. executar `foreign_key_check` e `integrity_check`;
6. provar restore do snapshot em teste;
7. só então atualizar versão operacional.

Não copiar apenas `.db` enquanto WAL está ativo. Backups recebem retenção e ficam fora do workspace.

No startup, o Core reconcilia runs `STARTING/RUNNING`, processos vivos, worktrees e leases. Um processo é identificado pelo conjunto atômico `process_id`, `process_started_at`, `process_image_sha256`, `host_boot_id` e `supervisor_token`; PID isolado não prova identidade. Efeito desconhecido resulta em `INTERRUPTED`, nunca `SUCCEEDED` inferido.

## Gatilhos de evolução

- FTS recall abaixo do alvo → índice semântico auxiliar.
- consultas frequentes e lentas em um campo JSON → promover campo/tabela com migration.
- mais de um writer/host → reavaliar topologia e banco.
- artifacts duplicados/volume medido → garbage collection por reachability e retenção.
- requisito de tamper evidence → hash chain/assinaturas, sem chamar isso de prevenção local absoluta.
