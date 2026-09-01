# APF — Contrato de intenção

`intent_revision: 1`

## Propósito

- Primário: `personal`
- Secundários: `open_source`, `experiment`
- Estado: arquitetura fundacional; não é um produto utilizável ainda.

## Problema

Agentes de IA conseguem produzir trabalho, mas o estado, as decisões, as evidências, os custos e os limites de autoridade se perdem entre sessões e fornecedores. Chat não é memória institucional e prompts não são mecanismos de segurança.

## Usuários

O primeiro usuário é um desenvolvedor solo que trabalha em um repositório Git local. A experiência futura deve servir também a pessoas que não dominam arquitetura, DevOps, FinOps ou orquestração de agentes, sem esconder riscos ou incertezas.

## Proposta de valor

APF mantém um controle determinístico sobre tarefas, permissões, aprovações e auditoria, usa modelos apenas em pontos explícitos de julgamento e preserva uma memória local consultável com referências internas.

## Hipótese principal

Um fluxo governado — intenção → tarefa limitada → execução → verificação → registro → explicação — reduz o tempo de retomada e aumenta a confiança em relação ao uso direto de um agente, sem impor custo e complexidade maiores que o benefício.

## Definição de sucesso da primeira prova

Em três tarefas reais sobre o próprio APF:

1. um Work Order limitado é executado por um provider CLI;
2. violações de escopo injetadas são detectadas em 3/3 casos;
3. interrupção não produz conclusão duplicada ou silenciosa;
4. uso, resultado, mudanças, verificações e decisões sobrevivem ao reinício;
5. `Ask Project` responde a um conjunto fixo de perguntas com referências internas válidas em pelo menos 90% dos casos;
6. o custo e o tempo do fluxo governado são comparados ao uso direto do provider.

## Escopo da primeira vertical slice

- `apf init`, `apf doctor`, `apf run`, `apf status` e `apf ask`;
- um projeto e uma execução ativa por vez;
- Codex como primeiro adapter e Claude como segundo adapter de conformidade;
- Project Brain em SQLite, SQL/FTS antes de embeddings;
- worktree Git por tarefa com diff e gates verificáveis;
- perfil `CONTROLLED` e subconjunto explícito de `SHARED`;
- custos reportados pelo provider, com fonte e confiança;
- Windows como plataforma de validação inicial; macOS e Linux permanecem arquitetados, mas não alegados como suportados até teste.

## Fora do escopo inicial

Studio completo, cloud APF, colaboração multi-humana, execução distribuída, A2A operacional, marketplace, plugins não confiáveis, vetores, organização dinâmica, lifecycle editor, catálogo de preços, Kubernetes, CRM, editor de código e autonomia geral.

## Governança

- Autonomia padrão: `CONTROLLED`.
- O Core determinístico, não um modelo, é o control plane.
- Nenhum processo de agente escreve diretamente no Brain ou no armazenamento de secrets.
- Estratégia, economia e áreas reguladas produzem análises com evidência; não recebem execução autônoma sem verificador mecânico e política específica.
- Telemetria APF: desativada por padrão.

## Recursos e restrições conhecidos

- Repositório e Git estão disponíveis localmente.
- Codex e Claude Code estão autenticados, mas Claude não está no `PATH`.
- Rust e Node não estavam instalados na inspeção inicial; Node foi adicionado somente em `.tools/` para validar JSON Schema, e toolchains futuros devem permanecer locais ao repositório sempre que possível.
- Capital e orçamento mensal ainda são `UNKNOWN`; nenhuma infraestrutura APF recorrente foi comprometida.
- O banco, backups e secrets devem permanecer fora do workspace entregue a agentes.

## Decisões pendentes de atenção humana

- Ratificar a licença MIT existente ou autorizar a recomendação Apache-2.0 antes de aceitar contribuições externas.
- Definir um envelope financeiro antes de habilitar APIs pagas ou infraestrutura recorrente além das assinaturas já existentes.
