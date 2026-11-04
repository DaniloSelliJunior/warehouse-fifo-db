-- =====================================================================
-- 02_regras.sql - Regras de negocio (gatilhos e funcoes) - PostgreSQL 16
--
-- O que este arquivo garante, alem das restricoes do 01_schema.sql:
--   R1. Especializacao TOTAL e DISJUNTA de ENDERECO e MOVIMENTACAO
--       (cada tupla da superclasse esta em exatamente a subclasse certa)
--   R2. Saldo de ESTOQUE_ENDERECO atualizado automaticamente a cada movimentacao
--   R3. Entrada so em endereco ativo, de zona que aceita a categoria e com espaco
--   R4. Nenhuma movimentacao de lote vencido
--   R5. Saida so do produto vendido e sem ultrapassar a quantidade do item
--   R6. Historico de movimentacoes imutavel (sem UPDATE/DELETE)
--   R7. Funcoes de operacao: sugerir endereco, registrar entrada e saida FIFO
-- =====================================================================

SET search_path TO estoque, public;

-- =====================================================================
-- R1. Especializacao total e disjunta
-- O esquema relacional (opcao 8A) nao garante isso sozinho. Dois gatilhos:
--   a) na subclasse (imediato): o tipo da superclasse precisa bater (disjuncao)
--   b) na superclasse (adiado para o COMMIT): a subclasse precisa existir (total)
-- Por isso a superclasse e a subclasse devem ser inseridas na mesma transacao.
-- =====================================================================

-- ---------- ENDERECO ----------
CREATE OR REPLACE FUNCTION fn_endereco_subclasse_confere() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_tipo   CHAR(2);
    v_espera CHAR(2);
BEGIN
    v_espera := CASE TG_TABLE_NAME
                    WHEN 'endereco_porta_pallet' THEN 'PP'
                    WHEN 'endereco_prateleira'   THEN 'PR'
                    WHEN 'endereco_piso'         THEN 'PI'
                END;
    SELECT Tipo_endereco INTO v_tipo FROM ENDERECO WHERE Id_endereco = NEW.Id_endereco;
    IF v_tipo IS DISTINCT FROM v_espera THEN
        RAISE EXCEPTION 'Endereco % e do tipo %, nao pode estar em %',
            NEW.Id_endereco, v_tipo, upper(TG_TABLE_NAME)
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER TG_END_PORTA_PALLET_TIPO BEFORE INSERT OR UPDATE ON ENDERECO_PORTA_PALLET
    FOR EACH ROW EXECUTE FUNCTION fn_endereco_subclasse_confere();
CREATE TRIGGER TG_END_PRATELEIRA_TIPO BEFORE INSERT OR UPDATE ON ENDERECO_PRATELEIRA
    FOR EACH ROW EXECUTE FUNCTION fn_endereco_subclasse_confere();
CREATE TRIGGER TG_END_PISO_TIPO BEFORE INSERT OR UPDATE ON ENDERECO_PISO
    FOR EACH ROW EXECUTE FUNCTION fn_endereco_subclasse_confere();

CREATE OR REPLACE FUNCTION fn_endereco_total_confere() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_existe BOOLEAN;
BEGIN
    -- o endereco pode ter sido apagado na mesma transacao
    IF NOT EXISTS (SELECT 1 FROM ENDERECO WHERE Id_endereco = NEW.Id_endereco) THEN
        RETURN NULL;
    END IF;
    v_existe := CASE NEW.Tipo_endereco
        WHEN 'PP' THEN EXISTS (SELECT 1 FROM ENDERECO_PORTA_PALLET WHERE Id_endereco = NEW.Id_endereco)
        WHEN 'PR' THEN EXISTS (SELECT 1 FROM ENDERECO_PRATELEIRA   WHERE Id_endereco = NEW.Id_endereco)
        WHEN 'PI' THEN EXISTS (SELECT 1 FROM ENDERECO_PISO         WHERE Id_endereco = NEW.Id_endereco)
    END;
    IF NOT v_existe THEN
        RAISE EXCEPTION 'Endereco % (tipo %) sem linha na subclasse correspondente',
            NEW.Codigo_endereco, NEW.Tipo_endereco
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER TG_ENDERECO_TOTAL
    AFTER INSERT OR UPDATE OF Tipo_endereco ON ENDERECO
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_endereco_total_confere();

-- ---------- MOVIMENTACAO ----------
CREATE OR REPLACE FUNCTION fn_mov_subclasse_confere() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_tipo   CHAR(1);
    v_espera CHAR(1);
BEGIN
    v_espera := CASE TG_TABLE_NAME WHEN 'entrada_estoque' THEN 'E' ELSE 'S' END;
    SELECT Tipo_mov INTO v_tipo FROM MOVIMENTACAO WHERE Id_movimentacao = NEW.Id_movimentacao;
    IF v_tipo IS DISTINCT FROM v_espera THEN
        RAISE EXCEPTION 'Movimentacao % e do tipo %, nao pode estar em %',
            NEW.Id_movimentacao, v_tipo, upper(TG_TABLE_NAME)
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER TG_ENTRADA_TIPO BEFORE INSERT ON ENTRADA_ESTOQUE
    FOR EACH ROW EXECUTE FUNCTION fn_mov_subclasse_confere();
CREATE TRIGGER TG_SAIDA_TIPO BEFORE INSERT ON SAIDA_ESTOQUE
    FOR EACH ROW EXECUTE FUNCTION fn_mov_subclasse_confere();

CREATE OR REPLACE FUNCTION fn_mov_total_confere() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF (NEW.Tipo_mov = 'E' AND NOT EXISTS
            (SELECT 1 FROM ENTRADA_ESTOQUE WHERE Id_movimentacao = NEW.Id_movimentacao))
    OR (NEW.Tipo_mov = 'S' AND NOT EXISTS
            (SELECT 1 FROM SAIDA_ESTOQUE WHERE Id_movimentacao = NEW.Id_movimentacao)) THEN
        RAISE EXCEPTION 'Movimentacao % (tipo %) sem linha na subclasse correspondente',
            NEW.Id_movimentacao, NEW.Tipo_mov
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER TG_MOV_TOTAL
    AFTER INSERT ON MOVIMENTACAO
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_mov_total_confere();

-- =====================================================================
-- R3 + R4. Validacoes antes de gravar a movimentacao
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_mov_valida() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_validade   DATE;
    v_categoria  INT;
    v_ativo      CHAR(1);
    v_zona       INT;
    v_capacidade INT;
    v_ocupado    INT;
BEGIN
    SELECT l.Data_validade, p.Id_categoria
      INTO v_validade, v_categoria
      FROM LOTE l JOIN PRODUTO p ON p.Id_produto = l.Id_produto
     WHERE l.Id_lote = NEW.Id_lote;

    -- R4: lote vencido nao entra nem sai (vai para descarte, fora do sistema)
    IF v_validade IS NOT NULL AND v_validade < NEW.Data_hora::date THEN
        RAISE EXCEPTION 'Lote % vencido em %', NEW.Id_lote, v_validade
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.Tipo_mov = 'E' THEN
        SELECT e.Ativo, e.Id_zona, e.Capacidade_max
          INTO v_ativo, v_zona, v_capacidade
          FROM ENDERECO e WHERE e.Id_endereco = NEW.Id_endereco;

        IF v_ativo <> 'S' THEN
            RAISE EXCEPTION 'Endereco % esta inativo', NEW.Id_endereco
                USING ERRCODE = 'check_violation';
        END IF;

        IF NOT EXISTS (SELECT 1 FROM ZONA_CATEGORIA
                        WHERE Id_zona = v_zona AND Id_categoria = v_categoria) THEN
            RAISE EXCEPTION 'A zona % nao aceita a categoria % (relacionamento ACEITA)',
                v_zona, v_categoria
                USING ERRCODE = 'check_violation';
        END IF;

        SELECT COALESCE(SUM(Quantidade), 0) INTO v_ocupado
          FROM ESTOQUE_ENDERECO WHERE Id_endereco = NEW.Id_endereco;
        IF v_ocupado + NEW.Quantidade_mov > v_capacidade THEN
            RAISE EXCEPTION 'Endereco % sem espaco: ocupado %, capacidade %, entrada %',
                NEW.Id_endereco, v_ocupado, v_capacidade, NEW.Quantidade_mov
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    RETURN NEW;
END $$;

CREATE TRIGGER TG_MOV_VALIDA BEFORE INSERT ON MOVIMENTACAO
    FOR EACH ROW EXECUTE FUNCTION fn_mov_valida();

-- =====================================================================
-- R2. Saldo por endereco (ESTOQUE_ENDERECO) sempre igual a
--     soma das entradas - soma das saidas daquele lote naquele endereco
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_mov_atualiza_saldo() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_saldo INT;
BEGIN
    IF NEW.Tipo_mov = 'E' THEN
        INSERT INTO ESTOQUE_ENDERECO (Id_lote, Id_endereco, Quantidade)
        VALUES (NEW.Id_lote, NEW.Id_endereco, NEW.Quantidade_mov)
        ON CONFLICT (Id_lote, Id_endereco)
        DO UPDATE SET Quantidade = ESTOQUE_ENDERECO.Quantidade + EXCLUDED.Quantidade;
    ELSE
        UPDATE ESTOQUE_ENDERECO
           SET Quantidade = Quantidade - NEW.Quantidade_mov
         WHERE Id_lote = NEW.Id_lote AND Id_endereco = NEW.Id_endereco
        RETURNING Quantidade INTO v_saldo;

        IF v_saldo IS NULL OR v_saldo < 0 THEN
            RAISE EXCEPTION 'Saldo insuficiente do lote % no endereco %',
                NEW.Id_lote, NEW.Id_endereco
                USING ERRCODE = 'check_violation';
        END IF;
        -- endereco liberado: remove a linha zerada
        IF v_saldo = 0 THEN
            DELETE FROM ESTOQUE_ENDERECO
             WHERE Id_lote = NEW.Id_lote AND Id_endereco = NEW.Id_endereco;
        END IF;
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER TG_MOV_SALDO AFTER INSERT ON MOVIMENTACAO
    FOR EACH ROW EXECUTE FUNCTION fn_mov_atualiza_saldo();

-- =====================================================================
-- R5. A saida precisa ser do produto vendido e nao pode passar do item
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_saida_confere_item() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_prod_lote INT;
    v_prod_item INT;
    v_qtd_item  INT;
    v_qtd_mov   INT;
    v_atendido  INT;
BEGIN
    SELECT l.Id_produto, m.Quantidade_mov INTO v_prod_lote, v_qtd_mov
      FROM MOVIMENTACAO m JOIN LOTE l ON l.Id_lote = m.Id_lote
     WHERE m.Id_movimentacao = NEW.Id_movimentacao;

    SELECT Id_produto, Quantidade_item INTO v_prod_item, v_qtd_item
      FROM ITEM_VENDA WHERE Id_item_venda = NEW.Id_item_venda;

    IF v_prod_lote <> v_prod_item THEN
        RAISE EXCEPTION 'O lote da saida e do produto %, mas o item % e do produto %',
            v_prod_lote, NEW.Id_item_venda, v_prod_item
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT COALESCE(SUM(m.Quantidade_mov), 0) INTO v_atendido
      FROM SAIDA_ESTOQUE s JOIN MOVIMENTACAO m ON m.Id_movimentacao = s.Id_movimentacao
     WHERE s.Id_item_venda = NEW.Id_item_venda;

    IF v_atendido + v_qtd_mov > v_qtd_item THEN
        RAISE EXCEPTION 'Item % ja atendido: vendido %, separado %, nova saida %',
            NEW.Id_item_venda, v_qtd_item, v_atendido, v_qtd_mov
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER TG_SAIDA_ITEM BEFORE INSERT ON SAIDA_ESTOQUE
    FOR EACH ROW EXECUTE FUNCTION fn_saida_confere_item();

-- =====================================================================
-- R6. Historico imutavel: erro se corrige com movimentacao de estorno,
--     nunca apagando ou alterando o registro
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_mov_imutavel() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% nao permitido em %: o historico de movimentacoes e imutavel',
        TG_OP, upper(TG_TABLE_NAME)
        USING ERRCODE = 'restrict_violation';
END $$;

CREATE TRIGGER TG_MOV_IMUTAVEL BEFORE UPDATE OR DELETE ON MOVIMENTACAO
    FOR EACH ROW EXECUTE FUNCTION fn_mov_imutavel();
CREATE TRIGGER TG_ENTRADA_IMUTAVEL BEFORE UPDATE OR DELETE ON ENTRADA_ESTOQUE
    FOR EACH ROW EXECUTE FUNCTION fn_mov_imutavel();
CREATE TRIGGER TG_SAIDA_IMUTAVEL BEFORE UPDATE OR DELETE ON SAIDA_ESTOQUE
    FOR EACH ROW EXECUTE FUNCTION fn_mov_imutavel();

-- =====================================================================
-- R7. Funcoes de operacao do deposito
-- =====================================================================

-- ---------- Sugere o endereco para guardar uma quantidade de um lote ----------
-- Criterio: endereco ativo, em zona que aceita a categoria, com espaco livre.
-- Preferencia: (1) endereco que ja guarda o mesmo produto (consolida),
--              (2) zona de RESERVA (picking fica livre para separacao),
--              (3) menor espaco livre que ainda cabe (melhor encaixe).
-- Retorna NULL se nenhum endereco comporta a quantidade.
CREATE OR REPLACE FUNCTION fn_sugerir_endereco(p_id_lote INT, p_quantidade INT)
RETURNS INT
LANGUAGE sql STABLE AS $$
    WITH alvo AS (
        SELECT l.Id_produto, p.Id_categoria
          FROM LOTE l JOIN PRODUTO p ON p.Id_produto = l.Id_produto
         WHERE l.Id_lote = p_id_lote
    ),
    livre AS (
        SELECT e.Id_endereco, e.Codigo_endereco, z.Funcao,
               e.Capacidade_max - COALESCE(SUM(ee.Quantidade), 0) AS Espaco_livre,
               BOOL_OR(l2.Id_produto = (SELECT Id_produto FROM alvo)) AS Mesmo_produto
          FROM ENDERECO e
          JOIN ZONA z            ON z.Id_zona = e.Id_zona
          JOIN ZONA_CATEGORIA zc ON zc.Id_zona = z.Id_zona
                                AND zc.Id_categoria = (SELECT Id_categoria FROM alvo)
          LEFT JOIN ESTOQUE_ENDERECO ee ON ee.Id_endereco = e.Id_endereco
          LEFT JOIN LOTE l2             ON l2.Id_lote = ee.Id_lote
         WHERE e.Ativo = 'S'
         GROUP BY e.Id_endereco, e.Codigo_endereco, z.Funcao, e.Capacidade_max
    )
    SELECT Id_endereco
      FROM livre
     WHERE Espaco_livre >= p_quantidade
     ORDER BY COALESCE(Mesmo_produto, FALSE) DESC,
              (Funcao = 'RESERVA') DESC,
              Espaco_livre,
              Codigo_endereco
     LIMIT 1;
$$;

-- ---------- Registra uma entrada (MOVIMENTACAO 'E' + ENTRADA_ESTOQUE) ----------
-- Se p_id_endereco for NULL, usa o endereco sugerido.
-- Retorna o Id_movimentacao criado.
CREATE OR REPLACE FUNCTION fn_registrar_entrada(
    p_id_lote        INT,
    p_quantidade     INT,
    p_id_funcionario INT,
    p_id_endereco    INT       DEFAULT NULL,
    p_data_hora      TIMESTAMP DEFAULT CURRENT_TIMESTAMP)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
    v_sugerido INT;
    v_endereco INT;
    v_id_mov   INT;
BEGIN
    v_sugerido := fn_sugerir_endereco(p_id_lote, p_quantidade);
    v_endereco := COALESCE(p_id_endereco, v_sugerido);

    IF v_endereco IS NULL THEN
        RAISE EXCEPTION 'Nenhum endereco disponivel para % unidades do lote %',
            p_quantidade, p_id_lote
            USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO MOVIMENTACAO (Tipo_mov, Data_hora, Quantidade_mov, Id_lote, Id_endereco, Id_funcionario)
    VALUES ('E', p_data_hora, p_quantidade, p_id_lote, v_endereco, p_id_funcionario)
    RETURNING Id_movimentacao INTO v_id_mov;

    INSERT INTO ENTRADA_ESTOQUE (Id_movimentacao, Id_endereco_sugerido)
    VALUES (v_id_mov, v_sugerido);

    RETURN v_id_mov;
END $$;

-- ---------- Registra a saida de um item de venda pela regra FIFO + validade ----------
-- Ordem de retirada (FEFO, depois FIFO):
--   1. lote que vence primeiro (sem validade fica por ultimo)
--   2. empate: lote recebido primeiro
--   3. dentro do lote: endereco de PICKING antes de RESERVA, menor saldo antes
--      (esvazia enderecos e libera espaco)
-- Lotes vencidos sao ignorados. Se o estoque valido nao cobre o item, nada e gravado.
-- Retorna uma linha por movimentacao criada.
CREATE OR REPLACE FUNCTION fn_registrar_saida_fifo(
    p_id_item_venda  INT,
    p_id_funcionario INT,
    p_data_hora      TIMESTAMP DEFAULT CURRENT_TIMESTAMP)
RETURNS TABLE (Id_movimentacao INT, Id_lote INT, Codigo_lote VARCHAR,
               Codigo_endereco VARCHAR, Quantidade INT)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
    v_produto    INT;
    v_falta      INT;
    v_disponivel INT;
    v_tirar      INT;
    v_id_mov     INT;
    r            RECORD;
BEGIN
    SELECT iv.Id_produto,
           iv.Quantidade_item - COALESCE((
               SELECT SUM(m.Quantidade_mov)
                 FROM SAIDA_ESTOQUE s JOIN MOVIMENTACAO m ON m.Id_movimentacao = s.Id_movimentacao
                WHERE s.Id_item_venda = iv.Id_item_venda), 0)
      INTO v_produto, v_falta
      FROM ITEM_VENDA iv
     WHERE iv.Id_item_venda = p_id_item_venda;

    IF v_produto IS NULL THEN
        RAISE EXCEPTION 'Item de venda % nao existe', p_id_item_venda;
    END IF;
    IF v_falta <= 0 THEN
        RETURN;   -- item ja totalmente atendido
    END IF;

    SELECT COALESCE(SUM(ee.Quantidade), 0) INTO v_disponivel
      FROM ESTOQUE_ENDERECO ee
      JOIN LOTE l     ON l.Id_lote = ee.Id_lote
      JOIN ENDERECO e ON e.Id_endereco = ee.Id_endereco
     WHERE l.Id_produto = v_produto
       AND e.Ativo = 'S'
       AND (l.Data_validade IS NULL OR l.Data_validade >= p_data_hora::date);

    IF v_disponivel < v_falta THEN
        RAISE EXCEPTION 'Estoque valido insuficiente do produto %: precisa %, disponivel %',
            v_produto, v_falta, v_disponivel
            USING ERRCODE = 'check_violation';
    END IF;

    FOR r IN
        SELECT ee.Id_lote, ee.Id_endereco, ee.Quantidade AS Saldo,
               l.Codigo_lote, e.Codigo_endereco
          FROM ESTOQUE_ENDERECO ee
          JOIN LOTE l        ON l.Id_lote = ee.Id_lote
          JOIN RECEBIMENTO rc ON rc.Id_recebimento = l.Id_recebimento
          JOIN ENDERECO e    ON e.Id_endereco = ee.Id_endereco
          JOIN ZONA z        ON z.Id_zona = e.Id_zona
         WHERE l.Id_produto = v_produto
           AND e.Ativo = 'S'
           AND (l.Data_validade IS NULL OR l.Data_validade >= p_data_hora::date)
         ORDER BY l.Data_validade NULLS LAST,
                  rc.Data_recebimento,
                  l.Id_lote,
                  (z.Funcao = 'PICKING') DESC,
                  ee.Quantidade,
                  e.Codigo_endereco
           FOR UPDATE OF ee
    LOOP
        EXIT WHEN v_falta = 0;
        v_tirar := LEAST(v_falta, r.Saldo);

        INSERT INTO MOVIMENTACAO (Tipo_mov, Data_hora, Quantidade_mov, Id_lote, Id_endereco, Id_funcionario)
        VALUES ('S', p_data_hora, v_tirar, r.Id_lote, r.Id_endereco, p_id_funcionario)
        RETURNING MOVIMENTACAO.Id_movimentacao INTO v_id_mov;

        INSERT INTO SAIDA_ESTOQUE (Id_movimentacao, Id_item_venda)
        VALUES (v_id_mov, p_id_item_venda);

        Id_movimentacao := v_id_mov;
        Id_lote         := r.Id_lote;
        Codigo_lote     := r.Codigo_lote;
        Codigo_endereco := r.Codigo_endereco;
        Quantidade      := v_tirar;
        RETURN NEXT;

        v_falta := v_falta - v_tirar;
    END LOOP;
END $$;

COMMENT ON FUNCTION fn_sugerir_endereco(INT, INT) IS
    'Endereco ativo, de zona que aceita a categoria e com espaco; prefere consolidar o produto';
COMMENT ON FUNCTION fn_registrar_entrada(INT, INT, INT, INT, TIMESTAMP) IS
    'Grava MOVIMENTACAO (E) + ENTRADA_ESTOQUE; o saldo e atualizado pelo gatilho';
COMMENT ON FUNCTION fn_registrar_saida_fifo(INT, INT, TIMESTAMP) IS
    'Atende um item de venda pela ordem validade -> recebimento (FEFO/FIFO)';
