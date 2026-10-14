# Controle Financeiro Igreja

Aplicativo Flutter offline-first para gestão financeira de igrejas. Os dados permanecem no aparelho; não há servidor, Firebase ou API externa. O APK publicado está disponível na área **Releases**.

Este repositório contém o projeto-fonte completo. O arquivo `PIRITUBA-APP-source.zip` também fornece um pacote pronto para extrair e abrir no Flutter.

## Executar e gerar APK

Instale Flutter (canal stable), Android Studio com Android SDK e Java 17. Na pasta do projeto, execute:

```powershell
.\build_android.ps1
```

O script gera as pastas nativas Android/iOS, baixa as dependências, executa a análise estática e compila o APK. O APK universal fica em `build\app\outputs\flutter-apk\app-release.apk`. O release exige um keystore próprio e as variáveis de ambiente `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` e `ANDROID_KEY_PASSWORD`; a compilação falha se estiverem ausentes. Não use nem publique a chave de debug como chave de distribuição, e mantenha o keystore e suas senhas fora do repositório. Guarde o keystore: atualizações Android precisam ser assinadas com a mesma chave. Para instalar diretamente, transfira o APK ao aparelho e abra-o; permita a instalação desse arquivo para o aplicativo que o abriu.

## Primeiro acesso

Na primeira execução, use **Cadastrar usuário** para criar o administrador. Informe também uma chave de recuperação e guarde-a com segurança. Ela é necessária para redefinir a senha offline.

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

Um APK não instala no iOS. A compilação de um app iOS requer macOS, Xcode e assinatura de desenvolvimento. Para distribuição sem publicação na App Store, é possível instalar um IPA assinado por desenvolvimento/ad hoc em aparelhos registrados, ou usar TestFlight (que exige App Store Connect). A pasta `ios` só pode ser criada/compilada pelo Flutter em macOS com Xcode instalado.

## Segurança do backup

O arquivo de backup contém o banco de dados local. Trate-o como informação financeira confidencial e compartilhe-o somente com pessoas autorizadas.
