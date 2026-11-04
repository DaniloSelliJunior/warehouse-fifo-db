-- =====================================================================
-- 03_visoes.sql - Visoes (views) usadas pelos relatorios - PostgreSQL 16
-- =====================================================================

SET search_path TO estoque, public;

-- ---------- Estoque detalhado: cada lote em cada endereco, com situacao da validade ----------
CREATE OR REPLACE VIEW VW_ESTOQUE_DETALHADO AS
SELECT p.Sku,
       p.Descricao                         AS Produto,
       c.Nome_categoria                    AS Categoria,
       l.Codigo_lote,
       l.Data_validade,
       l.Data_validade - CURRENT_DATE      AS Dias_para_vencer,
       CASE
           WHEN l.Data_validade IS NULL                    THEN 'SEM VALIDADE'
           WHEN l.Data_validade <  CURRENT_DATE            THEN 'VENCIDO'
           WHEN l.Data_validade <= CURRENT_DATE + 30       THEN 'VENCE EM 30 DIAS'
           ELSE 'OK'
       END                                 AS Situacao,
       z.Nome_zona                         AS Zona,
       z.Funcao,
       e.Codigo_endereco,
       ee.Quantidade,
       p.Unidade,
       r.Data_recebimento,
       l.Id_lote,
       l.Id_produto,
       e.Id_endereco
  FROM ESTOQUE_ENDERECO ee
  JOIN LOTE l        ON l.Id_lote = ee.Id_lote
  JOIN PRODUTO p     ON p.Id_produto = l.Id_produto
  JOIN CATEGORIA c   ON c.Id_categoria = p.Id_categoria
  JOIN RECEBIMENTO r ON r.Id_recebimento = l.Id_recebimento
  JOIN ENDERECO e    ON e.Id_endereco = ee.Id_endereco
  JOIN ZONA z        ON z.Id_zona = e.Id_zona;

-- ---------- Saldo por produto (valido x vencido) ----------
CREATE OR REPLACE VIEW VW_SALDO_PRODUTO AS
SELECT p.Id_produto,
       p.Sku,
       p.Descricao AS Produto,
       p.Unidade,
       COALESCE(SUM(d.Quantidade), 0)                                            AS Saldo_total,
       COALESCE(SUM(d.Quantidade) FILTER (WHERE d.Situacao <> 'VENCIDO'), 0)     AS Saldo_valido,
       COALESCE(SUM(d.Quantidade) FILTER (WHERE d.Situacao =  'VENCIDO'), 0)     AS Saldo_vencido,
       COUNT(DISTINCT d.Id_lote)                                                 AS Lotes,
       COUNT(DISTINCT d.Id_endereco)                                             AS Enderecos
  FROM PRODUTO p
  LEFT JOIN VW_ESTOQUE_DETALHADO d ON d.Id_produto = p.Id_produto
 GROUP BY p.Id_produto, p.Sku, p.Descricao, p.Unidade;

-- ---------- Fila FIFO: ordem em que cada produto sera retirado ----------
-- Mesma ordenacao de fn_registrar_saida_fifo (vencidos ficam de fora)
CREATE OR REPLACE VIEW VW_FILA_FIFO AS
SELECT d.Sku,
       d.Produto,
       ROW_NUMBER() OVER (
           PARTITION BY d.Id_produto
           ORDER BY d.Data_validade NULLS LAST, d.Data_recebimento, d.Id_lote,
                    (d.Funcao = 'PICKING') DESC, d.Quantidade, d.Codigo_endereco
       )                AS Ordem_saida,
       d.Codigo_lote,
       d.Data_validade,
       d.Data_recebimento,
       d.Codigo_endereco,
       d.Funcao,
       d.Quantidade
  FROM VW_ESTOQUE_DETALHADO d
  JOIN ENDERECO e ON e.Id_endereco = d.Id_endereco
 WHERE d.Situacao <> 'VENCIDO'
   AND e.Ativo = 'S';

-- ---------- Ocupacao de cada endereco ----------
CREATE OR REPLACE VIEW VW_OCUPACAO_ENDERECO AS
SELECT z.Nome_zona                                   AS Zona,
       e.Codigo_endereco,
       CASE e.Tipo_endereco WHEN 'PP' THEN 'Porta-pallet'
                            WHEN 'PR' THEN 'Prateleira'
                            WHEN 'PI' THEN 'Piso' END AS Tipo,
       e.Ativo,
       e.Capacidade_max,
       COALESCE(SUM(ee.Quantidade), 0)               AS Ocupado,
       e.Capacidade_max - COALESCE(SUM(ee.Quantidade), 0) AS Livre,
       ROUND(100.0 * COALESCE(SUM(ee.Quantidade), 0) / e.Capacidade_max, 1) AS Ocupacao_pct
  FROM ENDERECO e
  JOIN ZONA z ON z.Id_zona = e.Id_zona
  LEFT JOIN ESTOQUE_ENDERECO ee ON ee.Id_endereco = e.Id_endereco
 GROUP BY z.Nome_zona, e.Codigo_endereco, e.Tipo_endereco, e.Ativo, e.Capacidade_max;

-- ---------- Extrato de movimentacoes (rastreabilidade do lote) ----------
CREATE OR REPLACE VIEW VW_EXTRATO_MOVIMENTACAO AS
SELECT m.Id_movimentacao,
       m.Data_hora,
       CASE m.Tipo_mov WHEN 'E' THEN 'ENTRADA' ELSE 'SAIDA' END AS Tipo,
       p.Sku,
       l.Codigo_lote,
       e.Codigo_endereco,
       m.Quantidade_mov                                         AS Quantidade,
       f.Nome_funcionario                                       AS Funcionario,
       es.Codigo_endereco                                       AS Endereco_sugerido,
       iv.Id_venda,
       cl.Nome_cliente                                          AS Cliente
  FROM MOVIMENTACAO m
  JOIN LOTE l        ON l.Id_lote = m.Id_lote
  JOIN PRODUTO p     ON p.Id_produto = l.Id_produto
  JOIN ENDERECO e    ON e.Id_endereco = m.Id_endereco
  JOIN FUNCIONARIO f ON f.Id_funcionario = m.Id_funcionario
  LEFT JOIN ENTRADA_ESTOQUE en ON en.Id_movimentacao = m.Id_movimentacao
  LEFT JOIN ENDERECO es        ON es.Id_endereco = en.Id_endereco_sugerido
  LEFT JOIN SAIDA_ESTOQUE sa   ON sa.Id_movimentacao = m.Id_movimentacao
  LEFT JOIN ITEM_VENDA iv      ON iv.Id_item_venda = sa.Id_item_venda
  LEFT JOIN VENDA v            ON v.Id_venda = iv.Id_venda
  LEFT JOIN CLIENTE cl         ON cl.Id_cliente = v.Id_cliente;

COMMENT ON VIEW VW_ESTOQUE_DETALHADO    IS 'Saldo de cada lote em cada endereco, com situacao da validade';
COMMENT ON VIEW VW_SALDO_PRODUTO        IS 'Saldo total, valido e vencido por produto';
COMMENT ON VIEW VW_FILA_FIFO            IS 'Ordem de retirada de cada produto (validade, depois recebimento)';
COMMENT ON VIEW VW_OCUPACAO_ENDERECO    IS 'Capacidade, ocupacao e espaco livre por endereco';
COMMENT ON VIEW VW_EXTRATO_MOVIMENTACAO IS 'Historico de entradas e saidas com origem e destino';
