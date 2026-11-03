# Antigravity Global Config

Repositório privado para manter uma fonte central das customizações globais do Antigravity.

## O que é sincronizado

- `AGENTS.md`
- As nove skills listadas em `scripts/Publish-LocalConfig.ps1`

O sincronizador **não** copia toda a pasta `.gemini` e não sincroniza credenciais, permissões, MCP, plugins, configurações de interface ou dados de sessão.

## Requisitos

- Windows PowerShell 5.1 ou PowerShell 7+
- Git instalado
- A máquina autenticada no GitHub para clonar/puxar o repositório privado
- Executar os scripts com a conta Windows que possui o Antigravity e o perfil `.gemini` a sincronizar

## Primeira publicação (máquina principal)

1. Crie um repositório **privado** no GitHub, vazio, sem README/licença inicial.
2. Extraia este pacote para uma pasta local, por exemplo `C:\Users\<usuario>\source\antigravity-global-config`.
3. Abra PowerShell com a mesma conta Windows que utiliza o Antigravity.
4. Publique o `AGENTS.md` e as nove skills já instaladas:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Publish-LocalConfig.ps1 -ConfigRoot "$env:USERPROFILE\.gemini\config"
```

Se estiver usando uma sessão administrativa cujo `$env:USERPROFILE` não seja o perfil do Antigravity, **não use o caminho padrão**. Execute com `-ConfigRoot "C:\Users\felipetimbo\.gemini\config"` apenas se esse for realmente o perfil que deseja publicar.

5. Inicialize Git, faça commit e envie para o repositório privado:

```powershell
git init
git branch -M main
git add .
git commit -m "Initial Antigravity global configuration"
git remote add origin https://github.com/SEU-USUARIO/antigravity-global-config.git
git push -u origin main
```

Use o Git Credential Manager ou o fluxo de autenticação do GitHub. Não coloque token/senha na URL nem em scripts.

## Configurar outra máquina

1. Instale o Git e autentique-se no GitHub.
2. Extraia o pacote ou obtenha os scripts de bootstrap por um meio confiável.
3. Execute `Setup-AntigravitySync.ps1` apontando para o repositório privado:

```powershell
.\scripts\Setup-AntigravitySync.ps1 `
  -RepositoryUrl "https://github.com/SEU-USUARIO/antigravity-global-config.git"
```

O script clona o repositório em `%LOCALAPPDATA%\AntigravityGlobalSync\repo`, faz a primeira sincronização segura e registra uma tarefa agendada do Windows.

## Como a atualização automática funciona

- A tarefa roda ao entrar na sessão do Windows e também diariamente às 08:00.
- Também executa diariamente às 08:00.
- O atualizador executa `git pull --ff-only` e depois sincroniza apenas os itens gerenciados.
- Se o GitHub estiver indisponível, a configuração local permanece intacta e a próxima execução tenta novamente.

## Política de proteção contra sobrescrita

O sincronizador mantém estado local em:

`%LOCALAPPDATA%\AntigravityGlobalSync\state.json`

E backups em:

`%LOCALAPPDATA%\AntigravityGlobalSync\backups\<data-hora>\`

- Primeira instalação: se um destino já existir e for diferente da origem, o sincronizador cria backup e **não sobrescreve**; registra conflito para resolução manual.
- Atualização posterior: só atualiza um item se ele ainda corresponder exatamente à última versão sincronizada.
- Se uma cópia local tiver sido modificada, cria backup e preserva a cópia local, sem sobrescrevê-la.
- Itens removidos do repositório não são apagados automaticamente da máquina.
- Não há opção de sobrescrita forçada no atualizador automático.

Para resolver um conflito, compare o backup/local com a versão do repositório. Faça a mesclagem manual e só então execute novamente a sincronização. Não apague o arquivo de estado para “forçar” uma atualização sem antes guardar suas alterações.

## Desinstalar a automação

```powershell
Unregister-ScheduledTask -TaskName "AntigravityGlobalConfigSync" -Confirm:$false
```

Isso remove apenas a tarefa agendada. Não apaga o repositório clonado, os arquivos globais nem os backups.
