# Controle Financeiro Igreja

Aplicativo Flutter offline-first para Android. As informações são armazenadas no SQLite do próprio aparelho; não há servidor, Firebase ou API externa.

## Executar e gerar APK

Instale Flutter (canal stable), Android Studio com Android SDK e Java 17. Na pasta do projeto, execute:

```powershell
.\build_android.ps1
```

O script gera as pastas nativas Android/iOS, baixa as dependências, executa a análise estática e compila o APK. O APK universal fica em `build\app\outputs\flutter-apk\app-release.apk`. Para instalar diretamente em um Android, transfira esse arquivo para o aparelho e abra-o; permita a instalação desse arquivo para o aplicativo que o abriu. Também é possível instalar por USB com `flutter install`.

## Primeiro acesso

Na primeira execução, use **Cadastrar usuário** para criar o administrador. Informe também uma chave de recuperação e guarde-a com segurança. Ela é necessária para redefinir a senha offline.

## Recursos incluídos

- Login local com senha e chave de recuperação armazenadas como hashes.
- Dashboard, entradas, despesas, fluxo de caixa, cantina/vendas e compras, estoque, relatórios e configurações.
- SQLite local com transações, categorias, fornecedores, usuários, produtos e movimentações.
- Baixa automática do estoque em vendas da cantina e alertas de estoque baixo/zerado.
- Exportação de planilhas Excel, importação validada de XLSX, relatórios PDF e compartilhamento/exportação do backup local.
- Tema claro/escuro e dados da igreja.

As fórmulas `.xlsx` são gravadas no formato interno padronizado do Excel (nomes de funções em inglês); o Excel em português as exibe/localiza como `SOMA`, `SOMASE`, `SE` e `CONT.VALORES`.
O login é local e não substitui a proteção do aparelho: o SQLite não é criptografado. Proteja o celular e os backups com os recursos do sistema operacional.

## iPhone/iPad

Um APK não instala no iOS. A compilação de um app iOS requer macOS, Xcode e assinatura de desenvolvimento. Para distribuição sem publicação na App Store, é possível instalar um IPA assinado por desenvolvimento/ad hoc em aparelhos registrados, ou usar TestFlight (que exige App Store Connect). A pasta `ios` só pode ser criada/compilada pelo Flutter em macOS com Xcode instalado.

## Segurança do backup

O arquivo de backup contém o banco de dados local. Trate-o como informação financeira confidencial e compartilhe-o somente com pessoas autorizadas.
