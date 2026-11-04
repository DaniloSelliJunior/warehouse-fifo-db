-- =====================================================================
-- 01_fila_fifo.sql - Qual lote e qual endereco atendem o proximo pedido?
-- Ordem: validade mais proxima -> recebido primeiro -> picking antes de reserva
-- Uso: psql -d bd_deposito -f queries/01_fila_fifo.sql -v sku=TIN-ACR-18
-- =====================================================================
\if :{?sku}
\else
\set sku 'CIM-CPII-50'
\endif

SELECT Ordem_saida, Codigo_lote, Data_validade, Data_recebimento,
       Codigo_endereco, Funcao, Quantidade,
       SUM(Quantidade) OVER (ORDER BY Ordem_saida) AS Acumulado
  FROM VW_FILA_FIFO
 WHERE Sku = :'sku'
 ORDER BY Ordem_saida;
