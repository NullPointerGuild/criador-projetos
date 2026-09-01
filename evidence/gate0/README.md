# Evidência do Gate 0

Documentos fechados e sanitizados do Gate 0. Eles são projeções versionáveis, não a evidência bruta.

| Arquivo | Conteúdo |
|---|---|
| `gate0.schema.json` | JSON Schema Draft 2020-12 dos documentos fechados |
| `capability-matrix.v1.json` | controles do host e claims de provider, mantidos separados |
| `security-decisions.v1.json` | decisões `T0.8`, `T0.8a`, `T0.8b` e `T0.8c` |

## Custody

- A evidência bruta vive em scratch local untracked sob `.tmp/gate0/`. Não é copiada nem modificada aqui.
- Cada referência contém somente ID, classe, timestamp e SHA-256. Divergência de digest invalida o documento.
- Estes arquivos não contêm prompts, auth state, caminhos pessoais, output bruto do provider ou raciocínio privado.
- Mudança de binário, SO ou configuração invalida o claim correspondente e exige novo probe.

## Non-claims

1. Gate 0 não está fechado como um todo. `T0.8a` permite somente Slice 1 determinística; `T0.8b` continua incompleto.
2. Controles do host não são controles do provider e nunca são somados para fabricar enforcement mais forte.
3. `PROVIDER_ENFORCED` não é containment independente de SO.
4. Um caso positivo de escrita comum não prova contenção contra junction, hardlink, device path ou TOCTOU.
5. Rede real do provider não foi medida; só loopback do fixture foi observado.
6. `T0.8c` exige container/VM, mas nenhum baseline foi medido; na prática, conteúdo hostil é recusado.
7. Custo monetário real permanece `UNKNOWN`; tokens e estimativa de tabela não são gasto `ACTUAL`.
8. A classificação bruta do probe ativo permaneceu `UNKNOWN_OR_FAILED`. `DEF-01` registra a correção determinística derivada de campos brutos inalterados; o modelo não foi chamado novamente.
9. `UNKNOWN` e `NOT_EVALUATED` nunca viram `ALLOW`.
