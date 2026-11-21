# server/Services

Cada arquivo `.luau` nesta pasta é um ModuleScript carregado por `src/server/init.server.luau`.
Retorne uma tabela com métodos opcionais `:Init()` e `:Start()`.
O bootstrap chama todos os `:Init()` primeiro (em sequência) e depois executa cada `:Start()` em paralelo via `task.spawn`.
