-- =====================================================================
-- 03_saldo_e_ocupacao.sql - Quanto tenho de cada produto e onde ha espaco?
-- =====================================================================

-- Saldo por produto (valido x vencido)
SELECT Sku, Produto, Unidade, Saldo_total, Saldo_valido, Saldo_vencido, Lotes, Enderecos
  FROM VW_SALDO_PRODUTO
 ORDER BY Sku;

-- Ocupacao por zona
SELECT Zona,
       SUM(Capacidade_max) AS Capacidade,
       SUM(Ocupado)        AS Ocupado,
       ROUND(100.0 * SUM(Ocupado) / SUM(Capacidade_max), 1) AS Ocupacao_pct
  FROM VW_OCUPACAO_ENDERECO
 WHERE Ativo = 'S'
 GROUP BY Zona
 ORDER BY Ocupacao_pct DESC;

-- Enderecos vazios ou quase cheios
SELECT Zona, Codigo_endereco, Tipo, Ativo, Capacidade_max, Ocupado, Livre, Ocupacao_pct
  FROM VW_OCUPACAO_ENDERECO
 WHERE Ocupado = 0 OR Ocupacao_pct >= 90
 ORDER BY Ocupacao_pct DESC, Codigo_endereco;
