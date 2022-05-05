CREATE TABLE instruktorzy(
    id_instruktora INTEGER PRIMARY KEY,
    imie VARCHAR(50) NOT NULL,
    nazwisko VARCHAR(50) NOT NULL,
    telefon INTEGER UNIQUE NOT NULL,
    mail VARCHAR(50) UNIQUE NOT NULL,
    staz INTEGER NOT NULL,
    liczba_kursow INTEGER NOT NULL);

CREATE TABLE taniec(
    id_tanca INTEGER PRIMARY KEY,
    nazwa VARCHAR(50) NOT NULL
);

--czy tutaj rola jest potrzebna?
CREATE TABLE umiejetnosci_instruktora(
    id_instruktora INTEGER REFERENCES instruktorzy(id_instruktora) ON UPDATE CASCADE ON DELETE CASCADE,
    id_tanca INTEGER REFERENCES taniec(id_tanca) ON UPDATE CASCADE ON DELETE CASCADE,
    rola VARCHAR(50) NOT NULL
);

--bez roli bo moga tanczyz w roznych tancach + role ciezko sprawdzic czy sie zgadza przy np dodawaniu na zajeica;
CREATE TABLE klienci(
    id_klienta INTEGER PRIMARY KEY,
    imie VARCHAR(50) NOT NULL,
    nazwisko VARCHAR(50) NOT NULL,
    telefon INTEGER UNIQUE NOT NULL,
    mail VARCHAR(50) UNIQUE NOT NULL,
    czy_oplacone BOOLEAN NOT NULL
);

--czy tu ta rola zostaje?
CREATE TABLE umiejetnosci_klienta(
    id_klienta INTEGER REFERENCES klienci(id_klienta) ON UPDATE CASCADE ON DELETE CASCADE,
    id_tanca INTEGER REFERENCES taniec(id_tanca) ON UPDATE CASCADE ON DELETE CASCADE,
    rola VARCHAR(50) NOT NULL
);
-- niech każdy taniec ma 8 lvl
--chyba lepiej bez tych id bo wtedy problem jak to sprawdzic czy id jest rzeczywiscie takie ze on jest follower czy leader?
CREATE TABLE zajecia(
    id_grupy INTEGER CHECK(id_grupy <= 8),
    id_tanca INTEGER REFERENCES taniec(id_tanca) ON UPDATE RESTRICT ON DELETE CASCADE,
    dzien_tygodnia VARCHAR(12) NOT NULL,
    godzina INTEGER NOT NULL CHECK (11 <= godzina AND godzina <= 21),
    liczba_leaderow INTEGER NOT NULL CHECK(liczba_leaderow <= 12),
    liczba_followerow INTEGER NOT NULL CHECK(liczba_followerow <= 12),
    PRIMARY KEY(id_grupy, id_tanca)
);
-- zrobic tabele zeby bylo id grupy id tanca i id trenerow

-- foreign key gwarantuje nam, ze np (czy primary key (id_grupy, id_tanca) na zajecia tez ma cos z tym wspolnego?)
-- select dodanie_uczestinka(3, 1, 3, 'leader');
-- wyrzuci blad gdy w tabeli zajecia nie ma (id_grupy, id_tanca)=(1, 3)
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

--------------------- PROCEDURALNY SQL -----------------------------

-- ZWIEKSZANIE STAZU I LEVELU GRUPY, TRIGGER STAZ
--uruchamiana pod koniec roku
CREATE OR REPLACE FUNCTION zmiana_grupy() RETURNS VOID AS $$
BEGIN
    IF id_grupy != 8 THEN
    UPDATE zajecia SET id_grupy = id_grupy + 1;
    END IF;
END;
$$ LANGUAGE 'plpgsql';

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


-- WYPLATY DLA INSTRUKTOROW
-- funkcja dodajaca krotki do tabeli wyplaty
CREATE OR REPLACE FUNCTION dodanie_wyplaty(id_instruktora_ INTEGER)
RETURNS VOID AS $$
DECLARE
    godz_pracy INTEGER;
    stawka INTEGER;
    pensja INTEGER;
BEGIN
    godz_pracy=(SELECT liczba_kursow FROM instruktorzy WHERE id_instruktora = id_instruktora_) * 6;
    stawka=25 + ((SELECT staz FROM instruktorzy WHERE id_instruktora = id_instruktora_) - 1) * 5;
    pensja=godz_pracy * stawka;
    INSERT INTO wyplaty VALUES(id_instruktora_, godz_pracy, stawka, pensja);
END;
$$ LANGUAGE 'plpgsql';

--dopisuje krotki do tabeli historia gdy usuwamy z tabeli wyplaty
CREATE OR REPLACE FUNCTION wyplaty_historia() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO historia VALUES (OLD.id_instruktora, old.godziny_pracy, old.stawka_godzinowa, old.pensja, current_timestamp)
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
        SELECT dodanie_wyplaty(krotka.id_instruktora);
    END LOOP;
END;
$$ LANGUAGE 'plpgsql';

-- na koniec kazdego miesiaca wykonujemy:
DELETE FROM wyplaty WHERE True;
SELECT for_wyplaty_instruktorzy();

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
