# Inspeção de ambiente

`initial_checked_at: 2026-08-28T21:20:00Z`  
`updated_at: 2026-08-31T15:10:00Z`  
`host_scope: current machine and repository`  
`confidence: HIGH for observed facts`

## Repositório

- branch: `main`, acompanhando `origin/main`;
- commit inicial observado: `0eb04889fe09dc30d74db84e652628dd1256e055`;
- antes desta missão, somente `README.md` e `LICENSE` eram rastreados; `prompt.md` estava não rastreado;
- a licença presente no commit inicial é MIT, copyright 2026 NullPointerGuild;
- não havia código, package manager, CI, schema, testes nem instruções `AGENTS.md`; esses itens fundacionais foram adicionados depois da inspeção inicial;
- nenhum arquivo do usuário foi sobrescrito fora do escopo; `debug.log`, criado por um diagnóstico do VS Code, foi inspecionado e ignorado/removido.

## Sistema

Valores literais reportados pelo registro e runtime, sem inferir nome comercial:

| Item | Valor observado |
|---|---|
| OS description | Microsoft Windows 10.0.26200 |
| Registry ProductName | Windows 10 Pro |
| DisplayVersion | 25H2 |
| Build | 26200.9168 |
| Arquitetura | x64 |
| PowerShell | 5.1.26100.9168 |
| WSL | não instalado |

## Ferramentas observadas

| Ferramenta | Estado |
|---|---|
| Git | 2.55.0.windows.5 |
| VS Code | 1.135.0 |
| Codex CLI ativo | 0.151.0-alpha.7.2, SHA-256 `24a37127b8298b7bf96ca9b1d51a63c0685d561d1596f052bec73f734ed524b5` |
| Codex CLI histórico | 0.150.0-alpha.12.2, SHA-256 `b6e693173c2d526bff8400481197fbeafbd9fdcec43ca3471c9dc5f57565eb55` |
| Claude Code | 2.1.251, SHA-256 `8d1229a281281b98fd2dee72b3253a704be4fce4d45207200cd32a9bb5a6c909` |
| SQLite CLI | 3.53.4 instalado localmente em `.tools/`; FTS5 e threading ativos |
| Node.js/npm | 24.20.0 / 11.19.0 instalados localmente em `.tools/` somente para validação de schema |
| AJV / ajv-formats | 8.20.0 / 3.0.1 instalados localmente por lock e `npm ci --ignore-scripts` |
| .NET | runtimes 8.0.11, sem SDK |
| Rust/Cargo | 1.98.0 em `.tools/`, host `x86_64-pc-windows-gnu`; ausentes na inspeção inicial |
| C toolchain local | LLVM-MinGW 20260826 / Clang 23.1.0 em `.tools/` |
| pnpm/yarn/bun/deno | ausentes na inspeção inicial |
| Python utilizável | ausente; o alias WindowsApps não executa |
| Docker/Podman | ausentes |
| MSVC Build Tools (`cl`, `link`, `msbuild`) | ausentes |

Rust e Build Tools não foram instalados por antecipação. Node foi adicionado depois, localmente e apenas porque um validador genérico Draft 2020-12 fechou uma lacuna verificável da fundação. Após `T0.8a`, a Slice 1 fixou Rust `1.98.0`, rustup `1.29.0` e LLVM-MinGW `20260826` localmente. O bootstrap verifica o instalador rustup, o archive LLVM-MinGW, os executáveis C usados e o digest determinístico da árvore Rust instalada; os wrappers restauram o ambiente da sessão e não alteram `PATH` global. O alvo GNU compila Rust puro; LLVM-MinGW fornece o compilador C requerido pelo SQLite vendorizado e `dlltool` isolado para o linker Rust.

O Core fixa `rusqlite` no commit `a8f0a07bf65b28c05fa54b260d39707368ad9ed3`, com SQLite vendorizado `3.53.4`, FTS5 e backup habilitados. O runtime recusa SQLite abaixo de `3.53.4`. Isso continua distinto do SQLite CLI `3.53.4` usado pelo validador fundacional; cada versão é medida no seu próprio contexto.

`Cargo.lock` fixa a resolução. O wrapper restaura dependências com `cargo fetch --locked` e executa build/test com `--frozen`; a primeira restauração ainda pode exigir rede. A evidência sustenta repetição no host Windows medido, não build offline desde cache vazio nem identidade bit a bit. O bootstrap remove os proxies Cargo/rustc do home auxiliar depois de validar a toolchain e conserva apenas `rustup.exe`; proxies recriados não devem ser invocados diretamente porque, sem `RUSTUP_HOME` repo-local, rustup pode criar estado no perfil do usuário.

## Codex

- Configuração local observada: `model = "gpt-5.6-sol"`, `model_reasoning_effort = "ultra"`.
- `codex exec` oferece modo não interativo, sandbox explícito, JSONL e JSON Schema para a saída final; sem `--sandbox workspace-write`, exec inicia read-only na semântica documentada.
- `--ignore-user-config` ignora `config.toml`; qualquer backend Windows necessário ao probe deve ser reposto explicitamente. `--ignore-rules` se aplica à execpolicy, não ao autoload de `AGENTS.md`.
- O binário ativo foi medido uma vez com `windows.sandbox="elevated"`: read-only interno negou escrita, workspace-write interno criou o conteúdo esperado e um arquivo irmão comum permaneceu inalterado. Isso é provider-enforced para os casos medidos, não containment independente nem autorização de writes.
- O `app-server` existe, mas é marcado experimental no CLI instalado; não será a dependência inicial do adapter.
- O feature flag `mcp_2026_07_28` aparece como `under development`; suporte ao MCP mais recente deve ser detectado, não presumido.

Fontes oficiais verificadas em `2026-08-31`: [sandboxing](https://learn.chatgpt.com/docs/sandboxing), [non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode) e [Windows sandbox](https://learn.chatgpt.com/docs/windows/windows-sandbox). A documentação sustenta a semântica; os claims de enforcement dependem da evidência local por hash/configuração.

## Claude Code

- O comando não estava no `PATH`, mas o executável foi localizado em `anthropic.claude-code-2.1.251-win32-x64/resources/native-binary/claude.exe`.
- O diagnóstico confirmou instalação nativa funcional e autenticação; nenhum identificador de conta foi persistido nestes artefatos.
- A configuração local usa alias `opus` e `xhigh`; o CLI aceita `--effort max`.
- Uma revisão somente leitura foi executada com modelo canônico `claude-opus-5`, esforço `max`, `--restricted`, `--safe-mode` e sem persistência de sessão.
- Revisões somente leitura concluíram sem disponibilizar tools mutáveis. Nesta retomada, duas sessões diretas reportaram estimativa list-basis total de US$ 5.8095745; a chamada seguinte terminou em HTTP `429`, sem output ou custo. O acumulado direto registrado no projeto é US$ 16.4636515, ainda `ESTIMATED`; gasto real é `UNKNOWN`.
- O output persistido no repositório é somente síntese externa; prompts, auth state, output bruto e thinking privado não são copiados para a evidência fechada.
- A primeira tentativa falhou por bloqueio de rede do sandbox anterior; a segunda concluiu após a autorização explícita de acesso total. O adapter precisa distinguir falha de rede de falha lógica.

## SQLite local

Foi baixado o pacote oficial `sqlite-tools-win-x64-3530400.zip` para `.tools/`. O SHA3-256 calculado localmente foi:

```text
88b4659fe747896b853af10157316b4ade143553efb89c1c8ca7423a278dcc8b
```

Ele coincide com o hash publicado pelo projeto SQLite. A instalação não alterou `PATH` ou configuração global.

## Node.js e validador local

Foi baixada a distribuição oficial `node-v24.20.0-win-x64.zip`. O SHA-256 verificado é:

```text
6cac9ffbca8f6a47091e4b5c772e0606049c3871cb67d900c0cedde630e545ba
```

AJV e `ajv-formats` são restaurados em `.tools/schema-validator` por `npm ci`, com integridades transitivas no lock versionado e lifecycle scripts desativados. Nada foi adicionado ao `PATH` ou ao npm global.

## Consequências

1. Windows x64 é a única plataforma que pode receber alegação de validação nesta máquina.
2. O primeiro adapter deve usar `codex exec`; app-server permanece candidato posterior.
3. Claude é utilizável por caminho descoberto, mas `apf doctor` deve oferecer remediação para o `PATH` sem alterá-lo silenciosamente.
4. Nenhuma promessa de container/WSL pode ser feita no ambiente atual.
5. O Core/CLI Rust já possui bootstrap local fixado e repetível no host medido, com as limitações de rede/bit-reprodutibilidade acima. Tauri/WebView2 e a necessidade de MSVC para o Studio continuam não verificados e fora da Slice 1.
6. Gate 0 permanece parcial: `T0.8a` permite a Slice 1 determinística sem provider runtime; `T0.8b` mantém todos os provider writes negados; conteúdo hostil é recusado até container/VM medido.
