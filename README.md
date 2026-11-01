# Controle Financeiro Igreja

Aplicativo Flutter offline-first para gestão financeira de igrejas. Os dados permanecem no aparelho; não há servidor, Firebase ou API externa. O APK publicado está disponível na área **Releases**.

Este repositório contém o projeto-fonte completo. O arquivo `PIRITUBA-APP-source.zip` também fornece um pacote pronto para extrair e abrir no Flutter.

## Executar e gerar APK

Instale Flutter (canal stable), Android Studio com Android SDK e Java 17. No Windows, crie uma chave de distribuição uma única vez e depois compile:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup_android_signing.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build_android.ps1
```

O primeiro script cria uma keystore em `%LOCALAPPDATA%\ControleFinanceiroIgreja` e guarda as credenciais protegidas pelo Windows para a conta atual. O segundo baixa as dependências, executa a análise estática e compila o APK universal em `build\app\outputs\flutter-apk\app-release.apk`. A chave e as credenciais ficam fora do repositório; não apague a keystore nem o perfil do Windows que protege as credenciais. Faça uma cópia de segurança segura da keystore. Atualizações Android precisam da mesma chave de assinatura; se a chave for perdida, será necessário publicar outro aplicativo ou desinstalar a versão existente antes de instalar uma assinada por outra chave. Para instalar diretamente, transfira o APK ao aparelho e abra-o; permita a instalação desse arquivo para o aplicativo que o abriu.

## Primeiro acesso

Na primeira execução, use **Cadastrar usuário** para criar o administrador. Informe também uma chave de recuperação e guarde-a com segurança. Ela é necessária para redefinir a senha offline. Os usuários criados depois pela tela de login recebem acesso somente para consulta; para cadastrar entradas e despesas, o administrador deve criar uma conta com perfil **Tesoureiro** (ou **Administrador**) em Configurações.

## Recursos incluídos

- Login local com senha e chave de recuperação armazenadas com PBKDF2-HMAC-SHA256; hashes de senhas legadas são atualizados no próximo login bem-sucedido e hashes de chaves legadas, na próxima recuperação de senha.
- Dashboard, entradas, despesas, fluxo de caixa, cantina/vendas e compras, estoque, relatórios e configurações.
- SQLite local com transações, categorias, fornecedores, usuários, produtos e movimentações.
- Baixa automática do estoque em vendas da cantina e alertas de estoque baixo/zerado.
- Exportação de planilhas Excel, importação validada de XLSX, relatórios PDF e compartilhamento/exportação do backup local.
- Tema claro/escuro e dados da igreja.

As fórmulas `.xlsx` são gravadas no formato interno padronizado do Excel (nomes de funções em inglês); o Excel em português as exibe/localiza como `SOMA`, `SOMASE`, `SE` e `CONT.VALORES`.
O banco local é criptografado com SQLCipher; a chave aleatória fica no armazenamento seguro do aparelho e o login do app continua obrigatório para acessar os dados. Na primeira abertura após a atualização, o banco SQLite existente é convertido e validado antes da substituição. Se a chave protegida for perdida, o banco criptografado não poderá ser recuperado. O backup automático do Android está desativado. Os backups exportados pelo app são arquivos SQLite sem criptografia para permitir restauração em outro aparelho; trate-os como informação financeira confidencial.

## iPhone/iPad

Um APK não instala no iOS. O workflow `ios-simulator-build` do Codemagic compila um app de simulador em macOS com Xcode; esse artefato serve somente para testes no simulador e não instala em iPhone/iPad. Para gerar um IPA para aparelhos, é necessária assinatura Apple Developer e um certificado/perfil de distribuição; para TestFlight, também é necessário acesso ao App Store Connect.

## Segurança do backup

O arquivo de backup contém o banco de dados local. Trate-o como informação financeira confidencial e compartilhe-o somente com pessoas autorizadas.
