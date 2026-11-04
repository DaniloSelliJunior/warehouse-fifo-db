-- =====================================================================
-- 07_metadados.sql - Dicionario de dados: tabelas, colunas e restricoes
-- No PostgreSQL o catalogo pode ser lido pelo padrao SQL (information_schema)
-- ou pelas tabelas proprias do sistema (pg_catalog). No psql: \dt, \d tabela.
-- =====================================================================

-- Tabelas do schema, comentario e quantidade exata de linhas
-- (query_to_xml executa um SELECT COUNT(*) dinamico para cada tabela)
SELECT c.relname AS Tabela,
       (xpath('/row/n/text()',
              query_to_xml(format('SELECT COUNT(*) AS n FROM %I.%I', n.nspname, c.relname),
                           FALSE, TRUE, '')))[1]::TEXT::INT AS Linhas,
       obj_description(c.oid, 'pg_class') AS Comentario
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'estoque' AND c.relkind = 'r'
 ORDER BY c.relname;

-- Colunas, tipos e obrigatoriedade
SELECT table_name AS Tabela, ordinal_position AS Pos, column_name AS Coluna,
       data_type AS Tipo, character_maximum_length AS Tam,
       is_nullable AS Aceita_nulo, is_identity AS Identidade
  FROM information_schema.columns
 WHERE table_schema = 'estoque'
   AND table_name IN (SELECT table_name FROM information_schema.tables
                       WHERE table_schema = 'estoque' AND table_type = 'BASE TABLE')
 ORDER BY table_name, ordinal_position;

-- Chaves estrangeiras: quem referencia quem
SELECT con.conname                 AS Restricao,
       con.conrelid::regclass      AS Tabela,
       pg_get_constraintdef(con.oid) AS Definicao
  FROM pg_constraint con
  JOIN pg_namespace n ON n.oid = con.connamespace
 WHERE n.nspname = 'estoque' AND con.contype = 'f'
 ORDER BY 2, 1;

-- Gatilhos das regras de negocio
SELECT event_object_table AS Tabela, trigger_name AS Gatilho,
       action_timing AS Momento, string_agg(event_manipulation, ', ') AS Eventos
  FROM information_schema.triggers
 WHERE trigger_schema = 'estoque'
 GROUP BY 1, 2, 3
 ORDER BY 1, 2;
