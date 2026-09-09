# Recall — prompt de construção 0→100

Você é o engenheiro responsável por construir o **Recall**, um app iPhone em Swift que grava áudio, transcreve no próprio aparelho, analisa a transcrição com IA on-device e mostra insights em gráficos. Referência de produto: o app "Slate" (gravação → transcrição → análise), porém extremamente simples, moderno e **sem nenhum servidor**. Tudo roda e fica no iPhone.

O trabalho termina quando o app compila limpo, os testes passam, e está pronto para eu instalar no meu iPhone via Xcode com conta Apple gratuita (Personal Team, perfil de 7 dias). Leia este documento inteiro antes de escrever a primeira linha.

---

## 1. Contexto e restrições fixas

- **Repo:** este diretório (`recall`), remoto `https://github.com/NicholasDhm/recall.git`, branch `main`, sem commits ainda.
- **Ambiente disponível:** macOS, Xcode 26.6, SDK iOS 26.5, simulador iOS 26.5, Swift 6.3. Não há `xcodegen` nem `tuist` instalados; pode instalar `xcodegen` via `brew install xcodegen`.
- **Plataforma:** iPhone only, iOS 26.0 mínimo. Sem iPad, sem Mac, sem watch.
- **Linguagem/stack:** Swift 6 (strict concurrency), SwiftUI, Observation (`@Observable`), SwiftData, AVFoundation, Speech (`SpeechAnalyzer` / `SpeechTranscriber`), FoundationModels, Swift Charts. **Zero dependências de terceiros.** Nenhum SDK externo, nenhum SPM package que não seja da Apple.
- **Sem servidor, sem rede.** O app não faz nenhuma chamada HTTP. Não há backend, não há chave de API, não há analytics de terceiros. Se algum recurso exigir rede, ele fica fora do escopo.
- **Conta Apple gratuita (Personal Team).** Isso impõe limites reais que você deve respeitar desde o início:
  - **Sem iCloud/CloudKit**, sem Push Notifications, sem App Groups, sem Sign in with Apple. Não adicione essas capabilities nem entitlements. O `SwiftData` roda com `cloudKitDatabase: .none`. Estruture o `ModelContainer` para que ativar CloudKit no futuro seja uma mudança de uma linha, mas **não ative**.
  - O perfil expira em 7 dias e o app precisa ser reinstalado pelo Xcode. Nada a fazer no código, só documentar.
  - Bundle ID deve ser único: use `com.nickdhm.recall`.
- **Idioma:** UI em **português do Brasil**. Código, identificadores, comentários e commits em **inglês**. Use um String Catalog (`Localizable.xcstrings`) desde o início com pt-BR como idioma de desenvolvimento, para não espalhar strings hard-coded.
- **Transcrição:** locale padrão `pt-BR`, com seletor para `en-US` nas configurações. Só locales que `SpeechTranscriber.supportedLocales` retornar.
- **Nunca diga "pronto" sem ter rodado o build e os testes.** Cole a saída resumida do `xcodebuild` na sua resposta final de cada fase. Se algo falhar, reporte a falha verbatim.

## 2. Regras de trabalho

- **Fases com commit.** Cada fase abaixo termina com build verde no simulador, testes passando e um commit. Um commit por fase, mensagem imperativa em inglês, corpo curto. **Nunca** adicione trailers `Co-Authored-By` ou `Claude-Session` nos commits. Faça `git push` ao final de cada fase.
- **Modelos econômicos para delegação.** Se você delegar trabalho a sub-agentes, use `haiku` para trabalho mecânico e `sonnet` para implementação bem especificada. **Nunca** use `fable`. Não delegue o que você mesmo resolve em poucas edições.
- **Verifique a API antes de usar.** `SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory` e `FoundationModels` são frameworks do iOS 26 e suas assinaturas podem diferir do que você lembra. Antes de escrever código contra elas, confira as interfaces reais no SDK instalado, por exemplo:
  ```
  xcrun --sdk iphoneos swift-demangle < /dev/null; \
  find "$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/Speech.framework" -name '*.swiftinterface' | head
  ```
  ou leia os `.swiftinterface` em `Speech.framework` e `FoundationModels.framework` dentro do SDK. Se um símbolo não existir, adapte; não invente.
- **Simplicidade acima de tudo.** Poucas telas, poucos arquivos, sem abstrações preventivas. Nenhum "Manager", "Coordinator", "Repository" genérico. Um serviço por responsabilidade real: gravação, transcrição, análise, armazenamento.
- **Comentários só para restrições que o código não expressa.** Nada de comentar o que a próxima linha faz.
- **Sem cor em números** a menos que a cor corresponda a um elemento visual no gráfico ao lado.
- **Acessibilidade básica:** labels em botões de ícone, Dynamic Type funcionando nas listas e no transcript.

## 3. Produto

### 3.1 Telas (4 abas + detalhe)

1. **Gravar** (`RecordView`) — tela inicial. Um botão grande de gravar/parar, timer, forma de onda simples (níveis do `AVAudioEngine`), e a **transcrição ao vivo** aparecendo abaixo enquanto grava. Ao parar, salva e abre o detalhe.
2. **Biblioteca** (`LibraryView`) — lista de gravações ordenada por data, com título, data, duração, primeiras palavras do resumo e chips de tags. Busca por texto no título, transcript e tags. Swipe para excluir (com confirmação). Botão para **importar áudio** do app Arquivos (`.fileImporter`, tipos `m4a`, `mp3`, `wav`, `aac`, `caf`): o arquivo importado entra na fila de transcrição.
3. **Insights** (`InsightsView`) — gráficos com Swift Charts sobre todas as gravações (seção 3.4).
4. **Ajustes** (`SettingsView`) — locale de transcrição, status do modelo de fala (baixado / baixando / não disponível, com botão para baixar), status do Apple Intelligence (disponível / indisponível e o motivo), espaço em disco usado pelas gravações, botão para apagar tudo (confirmação dupla), versão do app.
5. **Detalhe da gravação** (`RecordingDetailView`) — player com scrubber, transcript com timestamps e destaque do segmento atual durante a reprodução (tocar num segmento pula o áudio para ele), cartão de análise (resumo, tags, itens de ação), título editável, botões: reanalisar, compartilhar (exporta markdown com título, data, resumo, itens de ação e transcript), excluir.

### 3.2 Modelo de dados (SwiftData)

```swift
@Model final class Recording {
    var id: UUID
    var createdAt: Date
    var title: String
    var duration: TimeInterval
    var audioFileName: String        // relative to Application Support/Recordings/
    var localeIdentifier: String
    var source: Source               // .microphone | .imported
    var status: Status               // .recorded | .transcribing | .transcribed | .analyzing | .ready | .failed
    var failureReason: String?
    var transcriptText: String
    @Relationship(deleteRule: .cascade) var segments: [TranscriptSegment]
    var summary: String?
    var tags: [String]
    var actionItems: [String]
    var wordCount: Int
}

@Model final class TranscriptSegment {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var recording: Recording?
}
```

Regras: áudio em **AAC `.m4a`, mono, 32 kbps, 16 kHz** (formato definido em um único lugar). Arquivos ficam em `Application Support/Recordings/`, nunca em Documents. Excluir uma gravação exclui o arquivo. Nunca armazene URLs absolutas.

### 3.3 Pipeline

`Record` → `Transcribe` → `Analyze` → `Ready`. Cada etapa atualiza `status`. O pipeline roda em uma `actor` ou `Task` isolado, sobrevive à troca de aba, e é **retomável**: ao abrir o app, gravações em `.recorded` ou `.transcribed` voltam para a fila. Falhas ficam em `.failed` com `failureReason` legível e botão "Tentar de novo" no detalhe.

**Gravação:** `AVAudioEngine` com tap no input node alimentando ao mesmo tempo o arquivo (`AVAudioFile`) e o `SpeechAnalyzer` para transcrição ao vivo. `AVAudioSession` categoria `.playAndRecord`, modo `.spokenAudio` ou `.measurement`, `UIBackgroundModes: audio` no Info.plist para a gravação continuar com a tela bloqueada. Peça permissão de microfone na primeira gravação, com tela explicativa se negada.

**Transcrição:** `SpeechTranscriber` com o locale escolhido, `SpeechAnalyzer` consumindo o stream de buffers. Antes de transcrever, garanta o asset do locale: consulte `AssetInventory` e dispare o download com progresso visível se necessário. Preserve timestamps por segmento (use os `audioTimeRange` dos resultados finais). Para arquivos importados, use o caminho de arquivo do `SpeechAnalyzer` (analisar `AVAudioFile` direto). Guarde `wordCount` ao fim.

**Análise (FoundationModels):** verifique `SystemLanguageModel.default.availability` antes de qualquer coisa. Se disponível, use `LanguageModelSession` com saída estruturada via `@Generable`:

```swift
@Generable
struct TranscriptAnalysis {
    @Guide(description: "Resumo de 2 a 4 frases, em português do Brasil")
    var summary: String
    @Guide(description: "De 3 a 5 tags curtas em minúsculas, sem #", .count(3...5))
    var tags: [String]
    @Guide(description: "Itens de ação explícitos no texto; lista vazia se não houver")
    var actionItems: [String]
}
```

Transcripts longos excedem a janela do modelo on-device: divida em blocos (por segmentos, ~2.500 palavras), analise cada bloco, e faça uma passada final de consolidação. Se o modelo **não** estiver disponível (aparelho sem Apple Intelligence, desativado, ou modelo baixando), o app continua útil: `status` vai para `.ready` sem análise, o cartão mostra o motivo e a aba Insights usa só métricas determinísticas. Não trave o app nem o pipeline por falta de IA.

### 3.4 Insights (Swift Charts)

Todos calculados localmente a partir do SwiftData, sem IA. Período selecionável: 7 dias, 30 dias, tudo.

- Minutos gravados por dia (barras).
- Gravações por semana (barras).
- Palavras por minuto ao longo do tempo (linha), com média do período.
- Top 10 tags (barras horizontais), tocar numa tag filtra a Biblioteca.
- Top 20 palavras (lista com contagem), com stopwords pt-BR e en-US removidas; a lista de stopwords é um arquivo de recurso, não código.
- Cartões: total de gravações, total de horas, duração média, dia mais ativo.

Estado vazio bem desenhado quando não há gravações.

### 3.5 Design

Nativo iOS 26, componentes padrão SwiftUI, sem UI customizada onde o sistema resolve. Uma cor de destaque só. Ícone do app: gere um ícone simples (símbolo de onda/mic em fundo sólido) como PNG 1024×1024 via script e inclua no asset catalog; não deixe o ícone em branco. Dark mode funcionando. Haptics ao iniciar/parar gravação.

## 4. Fases e critérios de aceite

### Fase 0 — Esqueleto
- `brew install xcodegen`; crie `project.yml` gerando `Recall.xcodeproj` (target `Recall`, target de testes `RecallTests`). **Comite o `.xcodeproj` gerado também**, para eu abrir no Xcode sem rodar nada.
- Assinatura: `CODE_SIGN_STYLE = Automatic`, `PRODUCT_BUNDLE_IDENTIFIER = com.nickdhm.recall`, e `DEVELOPMENT_TEAM` vindo de um `Config/Local.xcconfig` **ignorado pelo git**, com um `Config/Local.xcconfig.example` comitado. Assim eu só preencho meu Team ID.
- `.gitignore` para Xcode/Swift. `CLAUDE.md` no repo com: comandos de build/test, as regras da seção 2 (commits, modelos econômicos, verificar API antes de usar, sem dependências, sem rede, limites da conta gratuita).
- Info.plist com `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `UIBackgroundModes: [audio]`, `UISupportedInterfaceOrientations` só portrait, `ITSAppUsesNonExemptEncryption = false`.
- App abre com `TabView` das 4 abas vazias. Build verde:
  ```
  xcodebuild -project Recall.xcodeproj -scheme Recall \
    -destination 'platform=iOS Simulator,name=<um iPhone do iOS 26.5, veja xcrun simctl list devices available>' \
    build test | tail -30
  ```
- Aceite: build e `test` passam, `git log` mostra o primeiro commit, push feito.

### Fase 1 — Gravação e biblioteca
- Modelo SwiftData, `ModelContainer` local, serviço de gravação, tela Gravar com timer e forma de onda, salvamento em `.m4a`, tela Biblioteca listando, excluindo e buscando por título. Detalhe com player e scrubber.
- Testes: formato de arquivo, cálculo de duração, exclusão remove o arquivo, busca.
- Aceite: gravar 10 segundos no simulador (o simulador usa o mic do Mac), ver na lista, reproduzir, excluir.

### Fase 2 — Transcrição on-device
- Download do asset de locale com progresso. Transcrição ao vivo durante a gravação. Transcrição de arquivos importados. Segmentos com timestamps e destaque na reprodução. Pipeline retomável e com estado de falha.
- Testes: quebra em segmentos, `wordCount`, retomada da fila a partir de cada `status`.
- Aceite: gravar falando em português e ver o texto aparecer ao vivo; importar um `.m4a` e ter o transcript em segundos.

### Fase 3 — Análise com Foundation Models
- Verificação de disponibilidade com motivo legível, `@Generable`, chunking para transcripts longos, cartão de análise, reanalisar, fallback completo quando indisponível.
- Testes: chunking (limites e ordem), consolidação, parsing de tags (minúsculas, sem duplicatas).
- Aceite: no simulador o modelo pode não estar disponível; então o fallback tem que ser visível e o pipeline chegar a `.ready`. Documente no README como testar num aparelho com Apple Intelligence.

### Fase 4 — Insights
- Todos os gráficos e cartões da seção 3.4, com período selecionável, estado vazio, tocar na tag filtra a Biblioteca.
- Testes: agregações por dia/semana, palavras por minuto, contagem de palavras com stopwords, top tags.
- Aceite: com 5 gravações de teste inseridas via preview/fixture, todos os gráficos renderizam com dados coerentes.

### Fase 5 — Acabamento e exportação
- Ajustes completos, compartilhar em markdown via `ShareLink`, título editável, ícone do app, haptics, String Catalog sem strings soltas, dark mode revisado, acessibilidade básica.
- Rode o app no simulador e tire screenshots de cada aba com `xcrun simctl io booted screenshot`; salve em `docs/screenshots/`.
- Aceite: build sem warnings de concorrência, testes verdes, screenshots comitados.

### Fase 6 — Pronto para o iPhone
- `README.md` com: o que é o app, arquitetura em um parágrafo, como buildar, e o **checklist de instalação no aparelho com conta gratuita**:
  1. No Xcode: Settings → Accounts → adicionar o Apple ID (Personal Team).
  2. Copiar `Config/Local.xcconfig.example` para `Config/Local.xcconfig` e preencher `DEVELOPMENT_TEAM` (o Team ID aparece em Signing & Capabilities ao selecionar o time).
  3. No iPhone: Ajustes → Privacidade e Segurança → Modo Desenvolvedor → ativar e reiniciar.
  4. Conectar por cabo, confiar no computador, selecionar o iPhone como destino no Xcode e Run.
  5. No iPhone: Ajustes → Geral → VPN e Gerenciamento de Dispositivo → confiar no desenvolvedor.
  6. Limites do Personal Team: perfil expira em 7 dias (basta rodar de novo pelo Xcode), máximo de 3 apps instalados por vez, sem iCloud.
- Confirme que `xcodebuild -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO` compila para dispositivo real (sem assinar). Isso pega erros que só aparecem fora do simulador.
- Commit final e push.

## 5. Entrega final esperada

Ao terminar a Fase 6, responda com:
- Saída resumida do último `xcodebuild ... build test` e do build `generic/platform=iOS`.
- Lista dos commits (`git log --oneline`).
- O que ficou fora do escopo ou não pôde ser verificado no simulador (por exemplo, Foundation Models), e exatamente como eu verifico no aparelho.
- Nenhum plano futuro, nenhuma sugestão de roadmap. Só o que foi feito e verificado.
