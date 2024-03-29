DROP TABLE IF EXISTS instruktorzy CASCADE;
DROP TABLE IF EXISTS taniec CASCADE;
DROP TABLE IF EXISTS klienci CASCADE;
DROP TABLE IF EXISTS zajecia CASCADE;
DROP TABLE IF EXISTS prowadzacy CASCADE;
DROP TABLE IF EXISTS uczestnicy_zajec CASCADE;
DROP TABLE IF EXISTS wyplaty CASCADE;
DROP TABLE IF EXISTS historia CASCADE;


CREATE TABLE instruktorzy(
    id_instruktora INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    imie VARCHAR(50) NOT NULL,
    nazwisko VARCHAR(50) NOT NULL,
    telefon INTEGER UNIQUE NOT NULL,
    mail VARCHAR(50) UNIQUE NOT NULL,
    staz INTEGER NOT NULL,
    liczba_kursow INTEGER NOT NULL DEFAULT 0);

CREATE TABLE taniec(
    id_tanca INTEGER PRIMARY KEY,
    nazwa VARCHAR(50) NOT NULL
);

CREATE TABLE klienci(
    id_klienta INTEGER GENERATED BY DEFAULT AS identity PRIMARY KEY,
    imie VARCHAR(50) NOT NULL,
    nazwisko VARCHAR(50) NOT NULL,
    telefon INTEGER UNIQUE NOT NULL,
    mail VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE zajecia(
    id_grupy INTEGER,
    id_tanca INTEGER REFERENCES taniec(id_tanca) ON UPDATE RESTRICT ON DELETE CASCADE,
    dzien_tygodnia VARCHAR(12) NOT NULL CHECK(dzien_tygodnia IN ('po','wt','śr','czw','pt')),
    godzina INTEGER NOT NULL CHECK (11 <= godzina AND godzina <= 21),
    liczba_leaderow INTEGER NOT NULL CHECK(liczba_leaderow <= 12),
    liczba_followerow INTEGER NOT NULL CHECK(liczba_followerow <= 12),
    PRIMARY KEY(id_grupy, id_tanca)
);

CREATE TABLE prowadzacy(
    id_grupy INTEGER,
    id_tanca INTEGER,
    id_instruktora_l INTEGER REFERENCES instruktorzy(id_instruktora) ON UPDATE CASCADE ON DELETE CASCADE,
    id_instruktora_f INTEGER REFERENCES instruktorzy(id_instruktora) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (id_grupy, id_tanca)
    REFERENCES zajecia(id_grupy, id_tanca) ON UPDATE CASCADE ON DELETE CASCADE
);


CREATE TABLE uczestnicy_zajec(
    id_klienta INTEGER REFERENCES klienci(id_klienta) ON UPDATE CASCADE ON DELETE CASCADE,
    id_grupy INTEGER,
    id_tanca INTEGER,
    rola VARCHAR(50) NOT NULL CHECK(rola IN ('leader', 'follower')),
    PRIMARY KEY (id_klienta, id_grupy),
    FOREIGN KEY (id_grupy, id_tanca)
    REFERENCES zajecia(id_grupy, id_tanca)
);

CREATE TABLE wyplaty(
    id_instruktora INTEGER PRIMARY KEY REFERENCES instruktorzy(id_instruktora) ON UPDATE CASCADE ON DELETE CASCADE,
    godziny_pracy INTEGER NOT NULL,
    stawka_godzinowa FLOAT NOT NULL,
    pensja DECIMAL(10,2) NOT NULL
);

CREATE TABLE historia(
    id_instruktora INTEGER NOT NULL,
    godziny_pracy INTEGER NOT NULL,
    stawka_godzinowa FLOAT NOT NULL,
    pensja DECIMAL(10,2) NOT null,
    czas TIMESTAMP NOT NULL,
    PRIMARY KEY (id_instruktora, czas)
    );
    
CREATE VIEW instruktorzy_grupa AS
     SELECT p.id_instruktora_l id_leader, 
     l.imie imie_leader, l.nazwisko nazwisko_leader,
     p.id_instruktora_f id_follower, 
     f.imie imie_follower, f.nazwisko nazwisko_follower,
     p.id_grupy, p.id_tanca FROM prowadzacy p 
     LEFT JOIN instruktorzy l 
     ON p.id_instruktora_l=l.id_instruktora 
     LEFT JOIN instruktorzy f ON 
     p.id_instruktora_f=f.id_instruktora;    

--------------------- PROCEDURALNY SQL -----------------------------

-- ZWIEKSZANIE STAZU, TRIGGER STAZ
--uruchamiana pod koniec roku

--uruchamiana pod koniec roku
CREATE OR REPLACE FUNCTION zmiana_stazu() RETURNS VOID AS $$
BEGIN
    UPDATE instruktorzy SET staz = staz + 1;
END;
$$ LANGUAGE 'plpgsql';

-- trigger staz += 1, if staz == 0
CREATE OR REPLACE FUNCTION niezerowy_staz() RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.staz = 0) THEN
        NEW.staz = 1;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';
CREATE TRIGGER niezerowy_staz BEFORE INSERT ON instruktorzy
    FOR EACH ROW EXECUTE PROCEDURE niezerowy_staz();


-- trigger uaktualniajacy liczbe kursow instruktora
CREATE OR REPLACE FUNCTION liczba_kursow_in() RETURNS TRIGGER AS $$
BEGIN
    UPDATE instruktorzy SET liczba_kursow = (SELECT count(*) FROM prowadzacy WHERE id_instruktora_l=instruktorzy.id_instruktora OR id_instruktora_f=instruktorzy.id_instruktora);
    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';
CREATE TRIGGER liczba_kursow_in AFTER INSERT OR UPDATE ON prowadzacy
    FOR EACH ROW EXECUTE PROCEDURE liczba_kursow_in();



-- WYPLATY DLA INSTRUKTOROW
-- funkcja dodajaca krotki do tabeli wyplaty
CREATE OR REPLACE FUNCTION dodanie_wyplaty(id_instruktora_ INTEGER)
RETURNS VOID AS $$
DECLARE
    godz_pracy INTEGER;
    stawka INTEGER;
    pensja INTEGER;
BEGIN
    godz_pracy = (SELECT liczba_kursow FROM instruktorzy WHERE id_instruktora = id_instruktora_) * 6;
    stawka = 25 + ((SELECT staz FROM instruktorzy WHERE id_instruktora = id_instruktora_) - 1) * 5;
    pensja = godz_pracy * stawka;
    INSERT INTO wyplaty VALUES(id_instruktora_, godz_pracy, stawka, pensja);
END;
$$ LANGUAGE 'plpgsql';

--dopisuje krotki do tabeli historia gdy usuwamy z tabeli wyplaty
CREATE OR REPLACE FUNCTION wyplaty_historia() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO historia VALUES (OLD.id_instruktora, old.godziny_pracy, old.stawka_godzinowa, old.pensja, current_timestamp);
    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';
CREATE TRIGGER wyplaty_historia BEFORE DELETE ON wyplaty
    FOR EACH ROW EXECUTE PROCEDURE wyplaty_historia();

-- funkcja robi petle for i dodaje wyplaty dla wszystkich instruktorow w tabeli instruktorzy
CREATE OR REPLACE FUNCTION for_wyplaty_instruktorzy() RETURNS VOID AS $$
DECLARE 
    krotka RECORD;
BEGIN
    FOR krotka IN SELECT * FROM instruktorzy LOOP
        PERFORM dodanie_wyplaty(krotka.id_instruktora);
    END LOOP;
END;
$$ LANGUAGE 'plpgsql';

-- na koniec kazdego miesiaca wykonujemy:
DELETE FROM wyplaty WHERE True;
SELECT for_wyplaty_instruktorzy();


-- DODAWANIE UCZESTNIKOW
-- zamiast insert into uzywamy tej funkcji, ona dodaje do zajecia i do uczestincy zajec
-- jak nie istnieje to utworz zajecia jak istnieje to update zajecia, insert into zajecia tylko poprzez funkcje dodanie_uczestnika
-- ta funkjca dodaje do zajecia i uczestincy_zajec
CREATE OR REPLACE FUNCTION dodanie_uczestnika(id_klienta_ INTEGER, id_grupy_ INTEGER, id_tanca_ INTEGER, rola_ VARCHAR(50), dzien VARCHAR(50), godzina INTEGER)
RETURNS VOID AS $$
BEGIN
    IF (((SELECT liczba_leaderow FROM zajecia WHERE id_grupy=id_grupy_ and id_tanca = id_tanca_) + (SELECT liczba_followerow FROM zajecia WHERE id_grupy=id_grupy_ and id_tanca = id_tanca_)) >= 24) THEN
            RAISE EXCEPTION 'Za dużo osob w sali.';
    END IF;
    IF (rola_ = 'follower') THEN
        IF (((SELECT liczba_leaderow FROM zajecia WHERE id_grupy=id_grupy_ and id_tanca = id_tanca_) IS NULL) AND ((SELECT liczba_followerow FROM zajecia WHERE id_grupy=id_grupy_ and id_tanca = id_tanca_) IS NULL)) THEN
            INSERT INTO zajecia VALUES (id_grupy_, id_tanca_, dzien, godzina, 0, 1);
        ELSIF (((SELECT liczba_leaderow FROM zajecia WHERE id_grupy=id_grupy_ and id_tanca = id_tanca_) + 2) < (SELECT liczba_followerow FROM zajecia WHERE id_grupy=id_grupy_ and id_tanca = id_tanca_)) THEN
            RAISE EXCEPTION 'Za duzo followerow.';
        ELSE
            INSERT INTO uczestnicy_zajec VALUES(id_klienta_, id_grupy_, id_tanca_, rola_);
            UPDATE zajecia SET liczba_followerow = liczba_followerow + 1 WHERE id_grupy=id_grupy_ and id_tanca = id_tanca_;
        END IF;
    ELSE
        IF (((SELECT liczba_leaderow FROM zajecia WHERE id_grupy=id_grupy_ and id_tanca = id_tanca_) IS NULL) AND ((SELECT liczba_followerow FROM zajecia WHERE id_grupy=id_grupy_ and id_tanca = id_tanca_) IS NULL)) THEN
            INSERT INTO zajecia VALUES (id_grupy_, id_tanca_, dzien, godzina, 1, 0);
        ELSIF ((SELECT liczba_leaderow FROM zajecia WHERE id_grupy=id_grupy_ and id_tanca = id_tanca_) > ((SELECT liczba_followerow FROM zajecia WHERE id_grupy=id_grupy_ and id_tanca = id_tanca_) + 2)) THEN
            RAISE EXCEPTION 'Za duzo leaderow.';
        ELSE
            INSERT INTO uczestnicy_zajec VALUES(id_klienta_, id_grupy_, id_tanca_, rola_);
            UPDATE zajecia SET liczba_leaderow = liczba_leaderow + 1 WHERE id_grupy=id_grupy_ and id_tanca = id_tanca_;
        END IF;
    END IF;
END;
$$ LANGUAGE 'plpgsql';


-- UPDATE NA TABELI ZAJECIA JESLI USUWAMY KLIENTA
-- trigger before delete on klienci, jesli klient rezygnuje z zajec to zmiejszamy liczba -1
-- delete on uczestincy_zajec bo jak usuwamy klienta to uczestincy_zajec maja cascade na id klienta i tez sie usuwaja
-- a w tabeli uczestincy_zajec jest id_grupy i id_tanca wiec mamy potrzebne dane do pomniejszenia o 1 liczby followerow/leaderow
CREATE OR REPLACE FUNCTION zmniejszenie_liczby() RETURNS TRIGGER AS $$
BEGIN
    IF (OLD.rola = 'leader') THEN
        UPDATE zajecia SET liczba_leaderow = liczba_leaderow - 1 WHERE id_grupy = OLD.id_grupy AND id_tanca = OLD.id_tanca;
    ELSE
        UPDATE zajecia SET liczba_followerow = liczba_followerow - 1 WHERE id_grupy = OLD.id_grupy AND id_tanca = OLD.id_tanca;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER zmniejszenie_liczby BEFORE DELETE ON uczestnicy_zajec
    FOR EACH ROW EXECUTE PROCEDURE zmniejszenie_liczby();


-- TRIGGER NA TABELI ZAJECIA, SPRAWDZANIE ZAJETEJ SALI
CREATE OR REPLACE FUNCTION zajeta_sala() RETURNS TRIGGER AS $$
DECLARE
    krotka RECORD;
BEGIN
    for krotka in select * from zajecia loop
        IF (NEW.dzien_tygodnia  = krotka.dzien_tygodnia) AND (new.godzina = krotka.godzina) THEN
            RAISE EXCEPTION 'Sala w ten dzien i o tej godzinie jest juz zajeta.';
        END IF;
    END loop;
    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER zajeta_sala BEFORE INSERT ON zajecia
    FOR EACH ROW EXECUTE PROCEDURE zajeta_sala();
