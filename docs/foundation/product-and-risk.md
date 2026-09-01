# Produto, premissas e riscos

## Definição de produto

### Problema

O uso direto de agentes produz resultados úteis, mas não oferece por si só uma fonte local e durável para responder: o que foi autorizado, quem executou, o que mudou, por quê, com qual evidência, quanto custou e o que deve acontecer depois.

### Público

- **V1:** desenvolvedor solo, um repositório Git, ambiente local/development e uma execução por projeto.
- **Depois da prova:** criadores não especialistas que precisam de uma experiência visual e progressiva.
- **Não atendido inicialmente:** equipes, produção, ambientes regulados e repositórios arbitrários não confiáveis.

### Valor

Continuidade, proveniência, governança e explicabilidade entre sessões e providers. “Organização de IA” é a visão; a unidade inicial de valor é um único ciclo governado e retomável.

### Diferenciação testável

APF só é produto se superar o uso direto do provider em pelo menos duas dimensões mensuráveis:

1. menor tempo e menor erro para retomar contexto;
2. melhor explicação/auditoria de mudanças e decisões;
3. capacidade real de impedir ou detectar efeitos fora do escopo;
4. custo marginal de governança aceitável.

Recursos que os providers já fornecem — subagentes, skills, hooks, MCP e worktrees — são reutilizados. Eles não constituem moat APF.

## MVP como experimento

**Hipótese:** um desenvolvedor confia mais e retoma mais rápido uma tarefa feita por agente quando existe Work Order limitado, verificação, estado durável e resposta citada.

**Investimento mínimo:** CLI, Core, Brain, um adapter, worktree, gates e cinco perguntas canônicas de `ask`.

**Critérios de sucesso:** definidos em `PROJECT.md`; nenhuma dashboard conta como validação.

**Critérios de falha:** ver a seção “Kill/pivot”.

## Registro de premissas

| ID | Premissa | Confiança | Impacto se falsa | Validação / gatilho | Estado |
|---|---|---:|---:|---|---|
| `ASM-001` | O primeiro usuário pode operar uma CLI durante a prova. | média | médio | dogfood antes do Studio | aberta |
| `ASM-002` | Continuidade e proveniência geram valor adicional aos recursos nativos dos providers. | baixa | crítico | comparar três tarefas APF versus provider direto | aberta |
| `ASM-003` | Codex e Claude oferecem execução não interativa, estrutura, cancelamento e observabilidade suficientes. | média | crítico | `SPIKE-001` e suíte de conformidade | parcial: estrutura confirmada; cancelamento/efeitos pendentes |
| `ASM-004` | SQLite suporta a carga local V1. | alta | médio | `SPIKE-003` com 100k eventos e readers durante escrita | aberta |
| `ASM-005` | Um conjunto honesto de controles pode ser implementado no Windows sem prometer contenção inexistente. | média | crítico | `SPIKE-002` com Job Object, environment scrub e AppContainer | aberta |
| `ASM-006` | SQL + FTS5 recupera contexto suficiente para `Ask Project`. | média | alto | 20 perguntas semânticas fixas; ≥90% de citações válidas | aberta |
| `ASM-007` | Um único provider é suficiente para provar o ciclo antes da abstração multi-provider. | alta | médio | Codex end-to-end, depois Claude na mesma suíte | aceita para V1 |
| `ASM-008` | Adiar o Studio não invalida a hipótese central. | alta | médio | concluir a prova CLI; testar UX visual em seguida | aceita para slice 1 |
| `ASM-009` | Usuários aceitam enviar contexto selecionado a um provider externo quando destino e escopo são visíveis. | baixa | alto | preview de contexto + entrevistas/dogfood | aberta |
| `ASM-010` | Escrita seletiva evita que o Brain acumule conteúdo sem valor. | média | alto | toda entidade deve responder a uma pergunta de produto | aberta |
| `ASM-011` | Produtividade suficiente em Rust pode ser obtida sem atrasar a prova. | média | alto | timebox do bootstrap/core; fallback documentado | aberta |

## Registro de riscos

Probabilidade e impacto são ordinais; não representam precisão estatística.

| ID | Categoria | Risco | Prob. | Impacto | Mitigação | Trigger / owner |
|---|---|---|---:|---:|---|---|
| `RISK-001` | produto | O prompt de 220 seções virar backlog literal. | alta | crítico | non-goals rígidos, fatias e gates | qualquer épico sem hipótese; Orchestrator |
| `RISK-002` | segurança | UI anunciar enforcement que o subprocesso pode contornar. | alta | crítico | níveis explícitos, veto a autonomia e testes adversariais | controle não demonstrado; Security |
| `RISK-003` | vendor | Mudança de CLI/modelo quebrar adapters. | alta | alto | capability probe por versão e suíte de conformidade | hash/versão mudou; Provider owner |
| `RISK-004` | conhecimento | Brain acumular “AI sludge” ou afirmações sem suporte. | média | alto | escrita seletiva, confidence, relations e `UNKNOWN` | registro sem pergunta/owner; Brain owner |
| `RISK-005` | economia | Governança custar mais tokens/tempo que o benefício. | média | crítico | contexto mínimo, modelo por impacto e experimento comparativo | overhead >2–3× sem ganho; FinOps |
| `RISK-006` | plataforma | Matriz Windows/macOS/Linux multiplicar falhas. | alta | alto | Windows validado primeiro; claims por plataforma | segundo SO antes do Gate 0; Platform |
| `RISK-007` | dados | Corrupção/migração destruir memória institucional. | baixa | crítico | backup antes de migração, integrity check, restore test | migração destrutiva; Brain owner |
| `RISK-008` | segurança | Secrets herdados ou rede permitirem exfiltração. | média | crítico | environment allowlist, secret refs, egress explícito | provider recebe secret; Security |
| `RISK-009` | produto | APF ser somente wrapper/log de Codex/Claude. | média | crítico | medir retomada, confiança e Ask Project | nenhum ganho após três tarefas; Product |
| `RISK-010` | finops | Custo reportado ser estimativa, não cobrança real. | alta | médio | guardar fonte, moeda, estado e confiança | provider sem recibo; FinOps |
| `RISK-011` | legal | Licença existente não refletir estratégia de patentes/ecossistema. | média | alto | `ATTN-001` antes de contribuições | primeira contribuição externa; Human |
| `RISK-012` | arquitetura | Rust/Tauri atrasar descoberta do domínio. | média | alto | CLI-first, timebox e fallback TypeScript | bootstrap domina a fatia; Architect |
| `RISK-013` | auditoria | Journal append-only ser confundido com tamper-proof. | média | alto | linguagem explícita e Brain fora do workspace | alegação de não repúdio; Security |

## Economia inicial

| Estado | Item | Valor | Fonte / confiança |
|---|---|---:|---|
| `ESTIMATED` | revisão Claude Opus 5 | US$ 1.4308935 | JSON do Claude Code, `costBasis=list`; alta para estimativa, desconhecida como cobrança |
| `ESTIMATED` | probes Claude Opus 5 | US$ 0.3139825 | schema/quoting/conformance, `costBasis=list` |
| `ESTIMATED` | probe Codex Luna | 11,857 tokens in / 120 out; custo `UNKNOWN` | evento `turn.completed`; sem campo monetário |
| `ACTUAL` | SQLite CLI | US$ 0 | download oficial gratuito; alta |
| `COMMITTED` | infraestrutura recorrente APF | US$ 0 | nenhuma contratação realizada |
| `UNKNOWN` | capital e orçamento mensal | — | requer `ATTN-002` antes de novo compromisso |

Tempo de engenharia é o principal custo provável. Não haverá catálogo de preços em V1; custos externos são armazenados com `checked_at`, moeda, fonte e confiança.

## Kill/pivot

Interromper a expansão e reconsiderar a proposta se, após três tarefas reais:

- o tempo de retomada e a correção humana não melhorarem frente ao provider direto;
- usuários não consultarem ou não confiarem no histórico;
- citações internas falharem em mais de 10% do conjunto fixo;
- escopo não puder ser pelo menos verificado de modo confiável no Windows;
- overhead governado permanecer acima de 2–3× sem ganho de qualidade;
- os CLIs não fornecerem contrato estruturado/cancelável suficiente;
- um template estático produzir a mesma organização que o futuro Organization Builder.

Pivot provável: produto menor de “memória e auditoria multi-provider”, sem pretensão de organização autônoma.
