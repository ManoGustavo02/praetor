# Praetor 1.5.0 — plano da interface nova

## O que tirei das referências

| Referência | O que aproveitar | O que NÃO pegar |
|---|---|---|
| Fontes (Pencil, Bubble, Cosmic, Madison, Lucy) | Títulos grossos e arredondados, com contorno escuro; números grandes e "gordinhos" | Fonte de nuvem/lápis no texto corrido (fica ilegível em 14px) |
| Comic Style UI Kit | **Contorno grosso + sombra dura deslocada** (cartoon), pílulas, abas em pílula, toggles redondos | O cinza claro como fundo único (no jogo cansa e some no mapa claro) |
| Kits wireframe / Silver | Botão com "degrau" de sombra que afunda ao clicar | O brilho metálico (datado) |
| Servidor MASSA (loading + TAB) | Cartões escuros translúcidos com **borda clara de 2px**, cabeçalho com logo e título grande, painel do jogador à direita, dica com "Próxima dica", barra de progresso com contorno, widget de música com equalizador, chip "ESC para fechar" | O layout igual, o amarelo igual, o nome e a logo. O nosso tem que ser reconhecível como Praetor |

## Identidade "Praetor Comic" (nome provisório)

- **Fundo**: escuro translúcido com desfoque leve (padrão) e tema claro "papel" opcional.
- **Forma**: cantos bem arredondados, borda clara de 2px, sombra dura deslocada 3px (sem desfoque). Hover levanta o cartão (sombra cresce); clique "afunda" (sombra some).
- **Cor de destaque**: configurável. Padrão dourado-imperial (Praetor = Roma), diferente do amarelo do MASSA. O cargo continua usando a própria cor e degradê.
- **Fontes (todas OFL)**:
  - títulos e números: **Lilita One** ou **Bagel Fat One**;
  - texto: **Nunito** (ExtraBold nos botões).
  - Vão dentro do addon (`resource/fonts`) com o arquivo de licença.
- **Animações em tudo**: abrir com "pop" de mola, listas entrando em cascata, números contando, abas deslizando, toasts quicando, chip do cargo com brilho passando, hover e clique com squish.
- **Sons**: clique, hover, pop, abrir, fechar e notificação (CC0 do Openverse), com volume e liga/desliga.

## Ícones

- O conjunto inteiro é refeito num estilo só: traço grosso arredondado, mesma grade 24×24 e mesmo peso, gerado de um conjunto MIT (Tabler/Phosphor) e retocado.
- A caveira e qualquer ícone deixam de ser esticados: o desenho passa a respeitar a proporção sempre (`UI.Icon` centraliza e encaixa).
- Os ícones de cargo continuam sendo do dono.

## O que muda (cada item pode ser desligado nas Configurações)

1. **Kit de widgets** (cl_widgets): botão, aba, cartão, campo, toggle, slider, dropdown, modal e toast, todos no estilo novo. Como tudo usa o kit, o menu inteiro já muda junto.
2. **Chat** redesenhado. Corrige também a caixa que perde e recupera o foco ao segurar o clique dentro do chat (o texto "Mensagem para todos" piscando).
3. **TAB**:
   - visual novo: cabeçalho com logo/nome do servidor, contador, cartão do jogador à direita;
   - **versão DarkRP**: grupos por profissão com a cor dela, procurado, licença;
   - **música opcional** enquanto está aberto.
4. **Tags acima da cabeça**: avatar, nome, cargo e profissão no DarkRP, com fade por distância. Podem ser desligadas.
5. **HUD de DarkRP**: vida, colete, dinheiro, salário, profissão e fome (se tiver). Substitui a do DarkRP e pode ser desligada.
6. **F4 de DarkRP** com abas Profissões, Loja (entidades, armas, munição, carregamentos, comida) e **barra de comandos de RP** (dropar dinheiro, dar dinheiro, vender portas, demitir, /advert...).
   - Lê as tabelas do próprio DarkRP: não precisa de sistema de profissão nosso.
   - Pode ser desligado.
7. **Tela de loading** com logo, nome, dicas que trocam, progresso real dos downloads e música de fundo. Liga/desliga.
   - Limite do GMod: a tela de loading **precisa ser uma página web** (`sv_loadingurl`); o Lua do addon ainda não roda nessa hora.
   - Plano: eu faço a página HTML e você hospeda de graça (GitHub Pages). O Praetor monta o link com as configurações do menu (nome, cor, dicas, música).
8. **Editor de ícone do cargo** com dois modos:
   - **Pixel**, o que já existe;
   - **Pintura**, novo: caneta, pincel, borracha, balde, tamanhos, cores e desfazer.
9. **Avisos, anúncios, votações, denúncias e tela de ban**: tudo no estilo novo.

## Oficina

- Os banners usam as mesmas fontes e o estilo de cartão novo, sempre com print real do jogo de fundo.
- O GIF vira a **logo do Praetor animada** no estilo da interface (pop, brilho, contorno sendo desenhado).

## Ordem de trabalho (por sessão, para caber nos créditos)

1. Fontes, kit de widgets, animações, sons e ícones (base de tudo).
2. Chat, TAB, tags e notificações.
3. DarkRP: TAB, HUD e F4.
4. Tela de loading (HTML) e música.
5. Editor de pintura, revisão geral, banners e GIF.

## Perguntas para você responder quando voltar

1. **Fonte dos títulos**: Lilita One (mais "gordinha e séria") ou Bagel Fat One (mais "bolha e cartoon")?
2. **Cor padrão de destaque**: dourado, roxo, azul ou outra?
3. **Músicas**:
   - me manda os arquivos/links que você quer para o TAB e o loading;
   - ou deixo só o campo para o dono colocar a dele.
4. **Hospedagem da tela de loading**: tudo bem usar GitHub Pages (grátis, eu deixo tudo pronto, você só sobe)?
5. **"Estilo do Aleph"** no GIF: é algum canal, artista ou logo específica? Me manda um exemplo.
