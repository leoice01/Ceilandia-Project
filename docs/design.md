# Documento de Design — Polícia e Ladrão PvP (Roblox)

## Visão geral

Um jogo de polícia e ladrão no Roblox em que o tiroteio é a atração principal. A cidade, os roubos e as gangs existem para gerar confrontos. A frase de venda é: "polícia e ladrão com o gunplay de um Warzone".

Diferencial. Jailbreak, Wanted e San Aurie são fortes em roubo, cidade e progressão, mas o combate deles é raso. Aqui, atirar e se mover precisa ser gostoso o bastante para o jogador ficar só por isso.

### Referências

| Referência | O que pegamos dela |
|---|---|
| COD Warzone | Gunplay tático, movimento fluido, TTK curto, loot de inimigos |
| PAYDAY | Estética de assalto, máscaras, preparação de golpes |
| Rob Run (Steam) | O momento de virar bandido, com fala e máscara (só a ideia; arte e falas próprias) |
| Extraction shooters | Risco depois do roubo: você só lucra se sobreviver com a grana |

### Pilares (toda decisão de design responde a pelo menos um)

1. Combate gostoso. Tiro responsivo, movimento fluido e feedback forte.
2. Risco e recompensa. Quanto maior o roubo, maior o alvo nas suas costas.
3. Poder de grupo. Gangs disputam território, ranking e os cofres umas das outras.
4. Identidade. Máscara, roupa e a animação de transformação mostram quem você é.

Público. Jogadores de Roblox de 13 anos ou mais que gostam de jogos de tiro e de jogar em grupo. Plataformas: PC primeiro, mobile com controles adaptados e console depois.

## Lições do Rob Run

O Rob Run (Kefir, Steam) prova que o conceito atrai muita gente: está entre os mais jogados da Steam. Mas tem só 52% de avaliações positivas em cerca de 70 mil reviews. Pegamos o que funciona e corrigimos o que os jogadores reclamam.

| O que funciona no Rob Run | Como fica no nosso jogo |
|---|---|
| Polícia e bandidos são todos jogadores reais | Igual: nada de polícia NPC caçando jogador (NPCs só como seguranças dentro dos roubos) |
| Esconderijo construído pelo jogador, com cofre, bancadas e lugar para guardar loot e veículos | A empresa da gang, num mapa separado, com cofre, fabricação e farm |
| Famílias do crime com cargos, raids coordenados, guerras e tréguas | Gangs com cargos, gang base, raids entre empresas e ranking |
| Esconderijo mais rico atrai mais raids | Igual, mas com proteções (janela de raid, parte do cofre protegida, escudo) |
| Transformação em bandido com fala e máscara | Igual, com máscaras personalizáveis e falas próprias |

| Reclamação dos jogadores (fonte) | Nossa resposta |
|---|---|
| Jogador solo morre o tempo todo para grupos | Proteção no spawn, roubos tier 1 feitos para jogar sozinho, recompensa maior por derrubar grupos |
| Falhas de login e servidores | Servidores do Roblox, salvamento com session locking e retry |
| Desempenho ruim | Meta de rodar em celular médio, StreamingEnabled e LOD |
| Wipes apagam o progresso | Sem wipe de progresso pessoal; só o ranking de gangs reinicia por temporada |

## Loop principal

O jogador vira bandido, rouba e precisa sobreviver com a grana até lavá-la. Entre o roubo e a lavagem, a polícia e os outros bandidos são ameaças ao mesmo tempo, e é aí que acontece o PvP.

O lucro vai para a empresa da gang, que fabrica o equipamento para roubos maiores. Preso ou morto, o jogador volta como civil. Quando morre, o loot fica no chão para quem chegar primeiro, seja policial ou bandido.

## Combate e movimentação

O combate é o produto. Ele é o primeiro sistema a ser construído, e nada mais entra no jogo antes de ele ficar gostoso em testes com jogadores reais.

### Gunplay

- TTK curto e consistente, próximo ao de um Warzone: quem atira primeiro e acerta vence. O valor exato sai dos testes.
- Recoil com padrão aprendível: o jogador melhora com a prática, sem depender de sorte. O spread só é aleatório no tiro sem mirar (hip fire).
- ADS (mirar) com zoom, sway leve e penalidade de movimento.
- Dano por região: cabeça, tronco e membros, com queda de dano por distância.
- Colete e capacete como camada de armadura que quebra, no estilo das placas do Warzone.
- Feedback: hitmarker, som de acerto diferente para cabeça e para armadura, kill feed, impacto de câmera e sons em camadas (perto, longe e eco).

Armas. O lançamento tem poucas armas, cada uma bem acertada: pistola, SMG, fuzil, escopeta e um rifle de precisão. Acessórios (mira, cano, carregador) vêm depois.

### Movimento

- Corrida tática, slide, mantle/vault em muros baixos, agachar e deitar.
- Lean (inclinar) nas quinas: é o que deixa o combate urbano tático.
- Animações em primeira e terceira pessoa feitas para o jogo, sem as animações padrão do Roblox.

### Derrubado (downed)

- Quando a vida zera, o jogador não morre na hora: ele cai no chão derrubado. Rasteja devagar, não pode atirar e sangra por um tempo limitado.
- Um aliado da mesma gang pode revivê-lo segurando um botão por alguns segundos, ficando exposto enquanto isso.
- O inimigo pode finalizar o derrubado com uma execução rápida ou deixá-lo sangrar até morrer.
- Um policial pode algemar um bandido derrubado. Essa é a forma principal de prisão.
- Kit de autorreanimação: item raro do mercado negro que deixa quem joga sozinho se levantar uma vez sem ajuda.
- O kill feed mostra quem derrubou e quem finalizou.

### Netcode e anti-exploit

- O cliente prevê o tiro e mostra o efeito na hora; o servidor valida e aplica o dano.
- Compensação de lag limitada: o servidor reconstrói a posição do alvo no momento do disparo, com um teto de tempo.
- O servidor confere linha de visão, distância, cadência, munição e ângulo. Tiro impossível é descartado e registrado.
- O cliente nunca decide dano, dinheiro, inventário ou estado de procurado.

## Facções e sistema de procurado

O jogador escolhe ser bandido ou policial. Civil é o estado neutro: não trabalha, não ataca e não pode ser atacado. Bandidos não são aliados entre si.

| Facção | Objetivo | Pode atacar | Ganha dinheiro com |
|---|---|---|---|
| Civil | Circular em paz e escolher um lado | Ninguém, e ninguém pode atacá-lo | Só o farm da empresa da gang |
| Bandido (procurado) | Roubar e sobreviver com a grana | Polícia e outros bandidos | Roubos e saque de outros bandidos |
| Polícia | Prender ou neutralizar procurados | Só procurados | Prisões (pagam mais) e abates (pagam menos) |

### Civil (neutro)

- Não tem trabalho. O jogador entra no servidor, escolhe ser bandido (com a animação da máscara) ou policial, e pode voltar a ser civil quando não estiver procurado.
- Tiros e golpes não causam dano em civis, e civis não podem atirar.
- A única forma de um civil morrer é por acidente, como ser atropelado ou pego numa explosão.
- Quem mata um civil por acidente ganha 1 estrela de procurado. Se for policial, perde a recompensa da próxima prisão. Isso evita usar o carro como arma contra civis.

Nível de procurado (1 a 5 estrelas). Sobe com o tamanho do crime e com policiais mortos. Mais estrelas significam mais polícia notificada, ícone no mapa por mais tempo e uma recompensa (bounty) maior pela cabeça do jogador.

### Prisão ou morte

- Prisão: o policial algema um bandido derrubado ou rendido. O bandido perde o dinheiro sujo que carregava e cumpre pena proporcional às estrelas. A polícia recebe o bônus maior.
- Morte: se o bandido derrubado for finalizado ou sangrar até o fim, ele larga o dinheiro sujo e parte dos itens no chão, e qualquer jogador pode saquear. Ele renasce sem pena.
- Prisão pagar mais que morte incentiva o jogo de polícia, em vez de virar só mata-mata.

Lavagem. O dinheiro roubado é "sujo" até ser entregue num ponto de lavagem ou no cofre da empresa. Só dinheiro limpo vai para o saldo permanente.

## Roubos

Os roubos são divididos em tiers. Quanto maior o tier, mais preparação, mais gente e mais estrelas de procurado ele exige, e mais ele paga. Os valores de pagamento e os tempos ficam para o balanceamento.

| Tier | Exemplos | Jogadores | Itens exigidos | Estrelas | Cooldown |
|---|---|---|---|---|---|
| 1 | Loja de conveniência, posto de gasolina | 1 | Nenhum | 1 | Curto, por loja |
| 2 | Joalheria, casa de câmbio | 1 a 2 | Pé de cabra ou chip hacker simples | 2 a 3 | Médio |
| 3 | Carro-forte, cassino | 2 a 4 | Chip hacker, C4 | 3 a 4 | Longo |
| 4 | Banco central, iate | 3 a 6 | Vários C4, chips avançados, veículo de fuga | 5 | Muito longo, global no servidor |

### Estrutura de um roubo grande (estilo PAYDAY)

1. Preparação: juntar C4, chips e equipamento no cofre da empresa.
2. Entrada: hackear câmeras, abrir portas e lidar com seguranças (NPCs).
3. Cofre: um minigame de hack ou um tempo de perfuração, enquanto o time defende a posição.
4. Fuga: a polícia e outros bandidos convergem; a grana pesa e deixa o jogador mais lento.
5. Lavagem: só o que chega ao destino conta.

Alerta global. Roubos de tier 3 e 4 avisam o servidor inteiro. Isso transforma cada roubo grande num evento de PvP: a polícia vem prender, e outras gangs vêm tomar a grana.

## Mercado negro

Todo roubo rende duas coisas: dinheiro sujo e itens. O dinheiro sujo é lavado; os itens só viram dinheiro quando vendidos no mercado negro. Isso cria uma segunda fuga depois do roubo e mais chances de PvP.

### Itens roubáveis

| Item | Onde se rouba | Tier | Detalhe |
|---|---|---|---|
| Eletrônicos (celulares, notebooks) | Loja de conveniência, lojas de eletrônicos | 1 | Leves, valem pouco, vendem rápido |
| Joias e relógios | Joalheria, casa de câmbio | 2 | Valor médio, ocupam pouco espaço |
| Barras de ouro | Carro-forte, banco | 3 a 4 | Muito valiosas e pesadas: deixam o jogador mais lento |
| Obras de arte | Iate, cassino | 3 a 4 | Precisam de dois jogadores para carregar |
| Documentos e cartões de acesso | Banco, iate | 3 a 4 | Não se vendem: abrem roubos maiores ou valem muito para um receptador específico |

### Como funciona a venda

- O receptador é um NPC que muda de lugar no mapa de tempos em tempos. Só quem tem o item na mão vê onde ele está.
- Item recém-roubado fica "quente" por um tempo. Vender quente paga menos e aumenta as estrelas de procurado. Esperar esfriar no cofre da empresa paga o preço cheio.
- O preço varia com a oferta: se muita gente vende o mesmo item, o preço cai até o estoque do receptador renovar.
- A venda paga em dinheiro limpo; o pagamento do mercado negro já é a lavagem do item.

### Riscos e PvP

- Itens ocupam espaço no inventário e na mochila. Mochila cheia deixa o jogador mais lento e visível.
- Quem morre derruba os itens que carrega. Qualquer jogador pode saquear e vender.
- O cofre da empresa guarda itens, e um raid pode levá-los.
- A polícia recebe bônus por apreender itens roubados ao prender um bandido.

O que o mercado negro vende. C4, chips hacker, armas ilegais e equipamento de roubo. Isso fecha o ciclo: rouba, vende, compra equipamento e faz um roubo maior.

## Gangs e empresas

A gang é o grupo social do jogo. Ela atua em dois lugares: no mapa principal, disputando a gang base, e num mapa separado, onde fica a empresa da gang.

### Gang base (mapa principal)

- Um ponto fixo no mapa que uma gang domina ao ocupar a área sem inimigos por um tempo, como um King of the Hill.
- Enquanto domina, a gang ganha pontos de ranking por minuto e um pequeno bônus de renda.
- Qualquer gang pode tentar tomar a base, então ela é um foco constante de tiroteio.
- Leaderboard global top 10 de gangs por pontos, com reset por temporada (por exemplo, mensal) e recompensas cosméticas exclusivas.

### Empresa (mapa separado)

- Cada gang tem uma sede que pode ser melhorada. Os membros entram por teleporte a partir da cidade.
- Farm: máquinas geram dinheiro com o tempo, inclusive AFK, com teto por hora e custo de manutenção.
- Cofre: guarda o dinheiro limpo e os itens de preparação (C4, chips hacker, armas).
- Fabricação: a empresa produz C4 e chips a partir de materiais, o que liga o farm aos roubos grandes.

### Raids entre empresas

- Uma gang invade a sede inimiga, quebra as defesas e rouba parte do cofre.
- Regras de proteção:
  - Raid só acontece com membros da gang alvo online, ou numa janela de horário fixa.
  - Uma parte do cofre é protegida e nunca pode ser roubada.
  - A gang raidada recebe um escudo temporário depois do ataque.
  - Iniciar um raid tem custo (C4 ou dinheiro), para não virar spam.
- O tamanho de gang é limitado (por exemplo, 8 a 12 membros) para que gangs gigantes não dominem tudo.

## Economia e progressão

Jogar ativamente (roubar, prender, dominar a base) sempre rende mais do que o farm AFK. O AFK é uma renda de apoio, não o caminho principal.

### Moedas

- Dinheiro sujo: o que se carrega durante o roubo; pode ser perdido na morte ou na prisão.
- Dinheiro limpo: o saldo permanente, usado em armas, veículos e melhorias da empresa.
- Moeda premium (Robux): só para cosméticos e conveniências. Nunca compra arma mais forte.

### Gastos (saídas de dinheiro)

- Armas, munição, coletes e acessórios.
- Veículos de fuga e de patrulha.
- Materiais para fabricar C4 e chips.
- Melhorias e manutenção da empresa.

### Progressão

- Nível de jogador separado para polícia e para bandido; cada um libera armas e roubos maiores.
- Maestria de arma: usar uma arma libera camuflagens e acessórios dela.
- Passe de temporada com recompensas grátis e premium, todas cosméticas.

## Personagem, cosméticos e monetização

A identidade visual é a principal fonte de receita, e toda a monetização é cosmética: nada que se compra com Robux dá vantagem no tiroteio.

### Transformação em bandido

- Uma animação curta (cerca de 2 a 3 segundos) em que o personagem fala uma frase e coloca a máscara.
- Câmera em close durante a animação, com som marcante. É o momento feito para virar clipe.
- Durante a animação o jogador fica vulnerável, então virar bandido no meio da polícia tem risco.
- Falas e animações próprias, sem copiar o Rob Run.

### Máscaras personalizadas

- Catálogo de máscaras base com cores, padrões e adesivos combináveis.
- Pacotes de "frase de transformação" (falas e gestos diferentes) vendidos como cosmético.
- Máscaras exclusivas de temporada e do top 10 de gangs.

### Roupas 3D

- Ternos, gravatas, coletes táticos e jaquetas feitos como modelos 3D próprios.
- Gravata e partes soltas se mexem com bones simples e balanço procedural, calculado só para jogadores próximos.
- Uniformes de polícia com variações por patente.

### Monetização

| Produto | Tipo |
|---|---|
| Máscaras, roupas, camuflagens de arma | Compra avulsa |
| Passe de temporada premium | Passe |
| Pacotes de frase e animação de transformação | Compra avulsa |
| Sede da empresa: decoração e visuais | Compra avulsa |
| VIP (servidor privado, vaga extra de garagem) | Game pass |

## Técnico e otimização

A meta é rodar liso em celular médio com um servidor cheio. Toda feature nova é testada nesse cenário antes de entrar.

### Arquitetura

- O servidor tem autoridade sobre dano, dinheiro, inventário, procurado, cofres e ranking. O cliente só envia intenções ("atirei nesta direção") e mostra o resultado.
- Código em módulos (ModuleScripts) organizados em servidor, cliente e compartilhado, com Luau tipado.
- Projeto versionado com Rojo e Git, para a equipe trabalhar junta sem conflito.

### Desempenho

- StreamingEnabled ligado, com o mapa dividido em regiões.
- Ricochetes, efeitos e física de roupa calculados só no cliente e só de perto (LOD).
- Replicação de tiros e movimento em pacotes compactos, sem mandar dados todo frame.
- Limite de NPCs e veículos ativos por servidor.

### Dados

- Salvamento com session locking, retry e autosave, para que jogador nenhum perca ou duplique itens.
- Cofres de empresa e ranking de gangs em DataStores separados, com controle de concorrência (dois membros mexendo no cofre ao mesmo tempo).
- Ranking global via OrderedDataStore ou MemoryStore, atualizado em lote.

### Segurança

- Validação e limite de frequência em todo RemoteEvent.
- Logs de ações suspeitas (tiro impossível, teleporte, dinheiro fora do esperado) para revisão e banimento.

Servidor. De 30 a 40 jogadores, a definir em teste de carga.

## Riscos e soluções

O maior risco é o escopo: este documento descreve trabalho de mais de um ano. Os outros riscos vêm de sistemas punitivos que afastam o jogador novo.

| Risco | O que acontece | Solução |
|---|---|---|
| Escopo grande demais | O jogo nunca sai | Lançar por fases; o primeiro público é o MVP de combate e roubo |
| Gunplay sem graça | Perde-se o diferencial inteiro | Protótipo de combate primeiro, com testes semanais com jogadores |
| Hacks (aimbot, silent aim) | Jogadores honestos saem | Validação no servidor desde o dia 1, logs e banimento |
| Raid com a gang offline | Sensação de perda injusta | Janelas de raid, parte protegida do cofre, escudo depois do raid |
| Farm AFK quebra a economia | Inflação, roubos perdem valor | Teto por hora, manutenção, AFK sempre rende menos que jogar |
| Novato morto em sequência | Sai no primeiro dia | Proteção no spawn, zonas seguras, recompensa maior por matar quem tem bounty alto |
| Gangs gigantes dominam | Ranking sempre igual | Limite de membros e reset por temporada |
| Celular fraco trava | Perde a maior parte do público do Roblox | Teste em mobile a cada fase, LOD agressivo |

## Roadmap e equipe

O jogo sai em fases, e cada uma é jogável sozinha. As datas ficam para depois que a equipe estiver definida.

A Fase 0 é a única que pode "falhar": se o tiroteio não ficar gostoso, o resto do plano não vale a pena. Os primeiros cosméticos (máscaras) já entram na Fase 1, junto com a transformação.

### Divisão do trabalho (4 pessoas)

Cada pessoa é dona de uma área inteira, e cada tarefa tem um único responsável. A montagem final do mapa passou para a Pessoa 3, que já faz os modelos. A Pessoa 4 fica só com o rascunho em blocos (greybox), o que alivia a carga dela.

| Pessoa | Área | Regra para saber se é dela | Dono de |
|---|---|---|---|
| P1 · Combate | Cliente | O que o jogador sente na mão | Armas, movimento, câmera, HUD, menus, veículos, minigames, física de roupa |
| P2 · Servidor | Sistemas | O que precisa ser seguro ou salvo | Validação de tiro, dano, derrubado, dados, economia, procurado, roubos, mercado negro, gangs, empresas, ranking |
| P3 · Arte 3D | Modelos e mapa | O que se vê parado | Armas, roupas, máscaras, itens, veículos, kit da cidade, montagem final do mapa |
| P4 · Design | Regras, animação e som | Como o jogo funciona e se mexe | Regras e valores, greybox dos roubos, animações, sons, playtests, Discord |

### Tarefas da Fase 0: protótipo de combate

| Tarefa | Responsável | Status |
|---|---|---|
| Montar o projeto: Rojo, Git e estrutura de pastas | P2 · Servidor | A fazer |
| Armas no cliente: tiro, recoil, spread e mira | P1 · Combate | A fazer |
| Validação de tiro e dano no servidor (regiões do corpo e colete) | P2 · Servidor | A fazer |
| Movimento: corrida, slide, mantle, agachar, deitar e lean | P1 · Combate | A fazer |
| Câmera, hitmarker, impacto e kill feed | P1 · Combate | A fazer |
| Derrubado, reviver e finalizar | P2 · Servidor | A fazer |
| Anti-exploit básico e logs de tiro | P2 · Servidor | A fazer |
| Modelos das 3 primeiras armas | P3 · Arte 3D | A fazer |
| Personagem base e arena de teste | P3 · Arte 3D | A fazer |
| Animações de arma: atirar, recarregar e mirar | P4 · Design | A fazer |
| Animações de movimento e de derrubado | P4 · Design | A fazer |
| Valores de dano, TTK e recoil | P4 · Design | A fazer |
| Sons de tiro e de impacto | P4 · Design | A fazer |
| Playtest semanal | Todos | A fazer |

### Tarefas da Fase 1: MVP jogável

| Tarefa | Responsável | Status |
|---|---|---|
| Escolha de lado: civil neutro, bandido ou polícia | P2 · Servidor | A fazer |
| Procurado (estrelas), bounty e algemas | P2 · Servidor | A fazer |
| Lógica dos roubos tier 1 e 2 | P2 · Servidor | A fazer |
| Inventário, mochila e peso (servidor) | P2 · Servidor | A fazer |
| Mercado negro, receptador e lavagem | P2 · Servidor | A fazer |
| Salvamento de dados com session locking | P2 · Servidor | A fazer |
| HUD, menus e tela de inventário | P1 · Combate | A fazer |
| Minigames de roubo: hack e arrombamento | P1 · Combate | A fazer |
| Veículos e atropelamento | P1 · Combate | A fazer |
| Física da gravata e das roupas | P1 · Combate | A fazer |
| Kit modular da cidade e montagem do mapa | P3 · Arte 3D | A fazer |
| Máscaras e roupas 3D (terno e gravata) | P3 · Arte 3D | A fazer |
| Itens roubáveis tier 1 e 2 e veículos | P3 · Arte 3D | A fazer |
| Animação da transformação em bandido | P4 · Design | A fazer |
| Greybox das lojas e da joalheria | P4 · Design | A fazer |
| Preços da economia e do mercado negro | P4 · Design | A fazer |
| Sons da cidade, dos veículos e da transformação | P4 · Design | A fazer |
| Teste em celular e otimização | Todos | A fazer |

A Pessoa 2 tem a fila mais longa na Fase 1. Se ela atrasar, a Pessoa 1 assume a parte de servidor dos minigames e dos veículos.

### Fases 2 a 5 (as tarefas detalhadas entram quando a Fase 1 acabar)

| Pessoa | Fases 2 e 3: gangs e empresas | Fases 4 e 5: roubos grandes e temporadas |
|---|---|---|
| P1 · Combate | Telas de gang e empresa, portas e C4 nos raids | Hack, perfuração e carga pesada nos roubos grandes; polimento |
| P2 · Servidor | Gangs, gang base, ranking, empresas, farm, cofre, raids | Lógica dos roubos grandes, alerta global, passe de temporada, loja |
| P3 · Arte 3D | Mapa das empresas, máquinas de farm, decoração das sedes | Banco, iate, cassino, carro-forte, cosméticos da loja |
| P4 · Design | Regras de raid e farm, greybox das sedes e da gang base | Greybox dos roubos grandes, animações de cosméticos, conteúdo das temporadas |

### Regras do time

- Quem é dono de uma área decide sobre ela. Os outros só mexem combinando antes.
- Cada um atualiza o Status das próprias tarefas nas tabelas acima.
- P1 e P2 revisam o código um do outro, principalmente tudo que passa entre cliente e servidor.
- Playtest com os 4 toda semana. A P4 anota o que foi testado e define as prioridades da semana seguinte.
- A P3 entrega modelos dentro de um limite combinado de polígonos e texturas, testados no celular.
- Código no Git (via Rojo) e mapa no Team Create.

## Perguntas em aberto

- [ ] Nome do jogo e identidade visual (cidade realista ou estilizada?)
- [ ] Câmera: terceira pessoa com ombro, primeira pessoa, ou as duas com troca?
- [ ] Quem das 4 pessoas fica com cada papel (Pessoa 1 a 4)? Alguém já tem experiência em Luau, modelagem ou animação?
- [ ] Policial pode atirar em quem tem só 1 estrela, ou só prender?
- [ ] Dinheiro e itens perdidos ao morrer: tudo o que se carrega ou uma porcentagem?
- [ ] Tamanho máximo de gang e duração da temporada do ranking.
- [ ] Polícia: qualquer jogador pode entrar, ou existe limite de proporção entre polícia e civis?

## Fontes

- Rob Run — games.gg
- Rob Run ganha popularidade na Steam — games.gg
