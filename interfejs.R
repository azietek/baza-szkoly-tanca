library(shiny)
library('ggplot2')
library('RPostgreSQL')
library(shinyjs)
library(V8)
library(shinyWidgets)
pg <- dbDriver("PostgreSQL")
con <- dbConnect(pg, user="aleksandra", password="456789",
                 host="localhost", port=5432, dbname="project")


ui <- fluidPage(
  setBackgroundColor(
    color = c("#8edfe8", "#de3a68"),
    gradient = "linear",
    direction = "bottom"
  ),
  
  titlePanel("Baza szkoły tańca"),
  sidebarLayout(
    sidebarPanel(
      p('Wybierz klienta do analizy'),
      
      selectInput(inputId = "kli_id", 
                  label = "Wybierz ID",
                  choices = ids,
                  selected=1),
      
      p('Wybierz grupę do analizy'),
      
      selectInput(inputId = "taniec_", 
                  label = "Wybierz nazwę tańca",
                  choices = tance,
                  selected = "Charlestone"),
      
      selectInput(inputId = "poziom", 
                label = "Wybierz numer grupy",
                choices = poziomy,
                selected=1)

      
    ),
    
    mainPanel(
      tabsetPanel(id='tabset',
        tabPanel("Wybrany klient", p("Wszystkie umiejętności i przynależenia do grup klienta:"), 
                 verbatimTextOutput('ten_klient')),
                 
        tabPanel("Wybrana grupa", p("Dane dotyczące podanej grupy:"),
                 verbatimTextOutput('grupa_info'),
                 verbatimTextOutput('ta_grupa')),
        
        tabPanel("Klienci", p("Dane dotyczące każdego klienta:"), 
                 
                 div(style="display:inline-block",textInput(inputId="imie_k_id",
                                                            label="Wpisz imię")),
                 
                 div(style="display:inline-block",textInput(inputId="nazwisko_k_id", 
                                                            label="Wpisz nazwisko")),
                 
                 div(style="display:inline-block",textInput(inputId="tel_k", 
                                                            label="Wpisz numer telefonu")),
                 
                 div(style="display:inline-block",textInput(inputId="mail_k", 
                                                            label="Wpisz maila")),
                 
                 
                 div(style="display:inline-block",actionButton("add_client", 
                                                               "Dodaj klienta")),
                 
                 div(style = "margin-top: 20px;"),
        
                 verbatimTextOutput("klienci")),

        
        tabPanel("Instruktorzy", p("Dane dotyczące każdego instruktora:"),
                 verbatimTextOutput("instruktorzy"),
                 
                 actionButton("exp_up", "Aktualizuj staż")),
      
        tabPanel("Zajęcia",
                 
                 p("Dodaj/usuń klienta z wybranej grupy"),
                 
                 div(style="display:inline-block",
                 selectInput(inputId = "id_k", 
                             label = "Wybierz ID klienta",
                             choices = ids,
                             selected = 1)),
                 
                 div(style="display:inline-block",
                 selectInput(inputId = "grupa_dod", 
                             label = "Wybierz numer grupy",
                             choices = c(1,2,3,4,5),
                             selected=1)),
                 
                 div(style="display:inline-block",
                 selectInput(inputId = "taniec_dod", 
                             label = "Wybierz rodzaj tańca",
                             choices = tance,
                             selected="Charlestone")),

                 awesomeRadio(
                   inputId = "role",
                   label = "Rola klienta", 
                   choices = c("leader", "follower"),
                   selected = "leader",
                   inline = TRUE, 
                 ),
                 
                 actionButton("add_client_group", "Dodaj klienta do grupy"),
                 actionButton("del_client_group", "Usuń klienta z grupy"),
                 
                 div(style = "margin-top: 20px;"),
                 
                 p("Jeśli chcesz zwiększyć poziom grup, kliknij przycisk 
                   'Aktualizuj grupy' (rekomendowane działanie na koniec roku)"),
                 
                 actionButton("group_up", "Aktualizuj poziom grup"),
                 
                 div(style = "margin-top: 20px;"),
                 
                 p("Dane każdych zajęć:"),
                 
                 verbatimTextOutput("zajecia"),
              
                 ), 
        
        tabPanel("Uczestnicy zajęć", p("Uczestnicy zajęć:"),
                 verbatimTextOutput("uczestnicy")),
                 
        
        tabPanel("Wypłaty", p("Przewidywane wypłaty dla instruktorów w obecnym miesiącu:"), 
                 verbatimTextOutput("wyplaty"), 
                 
                p('Po kliklnięciu wypłaty z tego miesiąca przejdą do historii'), 
                                    
                actionButton("payment", "Wypłata")), 
        
        tabPanel("Historia wypłat", p("Historia wypłat:"), 
                  verbatimTextOutput("historia"))
      )
    )
  )
)

server <- function(input, output, session) {

  output$ten_klient = renderPrint({
    query1 <- paste("SELECT k.id_klienta, k.imie, k.nazwisko, u.id_grupy, t.nazwa 
    FROM klienci k INNER JOIN uczestnicy_zajec u USING(id_klienta) INNER JOIN 
                    taniec t USING(id_tanca) where id_klienta=", input$kli_id)
    
    ten_klient <- dbGetQuery(con, query1)
    ten_klient
  })
  
  output$grupa_info = renderPrint({
    taniec <- paste0("'",input$taniec_,"'")
    query1 <- paste("SELECT id_tanca FROM taniec WHERE nazwa=", taniec)
    nr_tanca <- dbGetQuery(con, query1)
    nr_tanca
    
    query <- paste("SELECT i.imie_leader imie_L, i.nazwisko_leader nazwisko_L,
    i.imie_follower imie_F, i.nazwisko_follower nazwisko_F, i.id_grupy, t.nazwa 
    FROM instruktorzy_grupa i LEFT JOIN taniec t USING(id_tanca) WHERE id_grupy=",
                   input$poziom, "AND id_tanca=", nr_tanca)
    grupa_info <- dbGetQuery(con, query)
    grupa_info
  })
  
  output$ta_grupa = renderPrint({
    taniec <- paste0("'",input$taniec_,"'")
    query1 <- paste("SELECT id_tanca FROM taniec WHERE nazwa=", taniec)
    nr_tanca <- dbGetQuery(con, query1)
    nr_tanca
    query2 <- paste("SELECT DISTINCT k.id_klienta, k.imie, k.nazwisko, u.rola FROM 
                    klienci k INNER JOIN uczestnicy_zajec u USING(id_klienta) 
                    INNER JOIN prowadzacy USING(id_grupy, id_tanca) WHERE u.id_grupy=", 
                    input$poziom," AND u.id_tanca=", nr_tanca, "ORDER BY k.id_klienta")
    ta_grupa <- dbGetQuery(con, query2)
    ta_grupa
  })
  
  output$klienci = renderPrint({
    klienci <- dbGetQuery(con, "SELECT k.id_klienta ID, k.imie, k.nazwisko, 
                          k.telefon, k.mail FROM klienci k ORDER BY k.id_klienta")
    klienci
  })
  
  
  observeEvent(input$add_client, {
    imie <- paste0("'",input$imie_k_id,"'")
    nazwisko <- paste0("'",input$nazwisko_k_id,"'")
    mail <- paste0("'",input$mail_k,"'")
    query1 <- paste("INSERT INTO klienci (imie, nazwisko, telefon, mail) 
                    VALUES(", imie, ",", nazwisko,",", input$tel_k, ",", mail,")")
    dbGetQuery(con,query1)
  })
  
  output$instruktorzy = renderPrint({
    instruktorzy <- dbGetQuery(con, "SELECT id_instruktora id_ins,
                               imie, nazwisko, telefon, mail, staz, liczba_kursow
                               nr_kurs FROM instruktorzy ORDER BY id_instruktora")
    instruktorzy
  })
  
  observeEvent(input$exp_up, {
    dbGetQuery(con, "SELECT zmiana_stazu()")
    updateTabsetPanel(session, 'tabset', selected=dbGetQuery(con, "SELECT * FROM instruktorzy"))
  })

  output$zajecia = renderPrint({
    zajecia <- dbGetQuery(con, "SELECT z.id_grupy grupa, t.nazwa taniec, 
    z.dzien_tygodnia dzien, z.godzina, p.id_instruktora_l in_lead, 
    p.id_instruktora_f in_follow, z.liczba_leaderow nr_lead, 
    z.liczba_followerow nr_foll FROM zajecia z JOIN prowadzacy p 
                          USING(id_tanca, id_grupy) 
                          JOIN taniec t USING(id_tanca) ORDER BY z.id_grupy;")
    zajecia
  })
  
  observeEvent(input$add_client_group, {
    
    taniec <- paste0("'",input$taniec_dod,"'")
    query1 <- paste("SELECT id_tanca FROM taniec WHERE nazwa=", taniec)
    id_tanca <- dbGetQuery(con, query1)
    
    rola <- paste0("'", input$role, "'")

    query2 <- paste("SELECT dzien_tygodnia FROM zajecia WHERE id_tanca=",
                    id_tanca, "AND id_grupy=", input$grupa_dod)
    dzien <- paste0("'", dbGetQuery(con, query2), "'")
    
    query3 <- paste("SELECT godzina FROM zajecia WHERE id_tanca=",
                    id_tanca, "AND id_grupy=", input$grupa_dod)
    godzina <- dbGetQuery(con, query3)
    
    query4 <- paste("SELECT dodanie_uczestnika(", input$id_k, ", ", 
                    input$grupa_dod, ", ", id_tanca, ", ", rola, ", ", dzien,
                    ", ", godzina, ")")
    dbGetQuery(con,query4)
    
  })
  
  observeEvent(input$del_client_group, {
    taniec <- paste0("'",input$taniec_dod,"'")
    query1 <- paste("SELECT id_tanca FROM taniec WHERE nazwa=", taniec)
    id_tanca <- dbGetQuery(con, query1)
    
    query2 <- paste("DELETE FROM uczestnicy_zajec WHERE id_klienta=", input$id_k,
                    "AND id_grupy=", input$grupa_dod, "AND id_tanca=", id_tanca)
    dbGetQuery(con,query2)
  })
  
  observeEvent(input$group_up, {
    dbGetQuery(con,"SELECT zmiana_grupy()")
  })
  
  output$uczestnicy = renderPrint({
    uczestnicy <- dbGetQuery(con, "SELECT k.id_klienta, k.imie, k.nazwisko, 
    u.id_grupy, t.nazwa taniec, u.rola FROM uczestnicy_zajec u LEFT JOIN taniec t 
    USING(id_tanca) LEFT JOIN klienci k USING(id_klienta) ORDER BY k.id_klienta")
    uczestnicy
  })
  
  output$wyplaty = renderPrint({
    wyplaty <- dbGetQuery(con, "SELECT i.id_instruktora id, i.imie, i.nazwisko, 
                          i.staz, i.liczba_kursow kursy, w.godziny_pracy, 
                          w.stawka_godzinowa stawka_godz, w.pensja 
                          FROM wyplaty w NATURAL JOIN instruktorzy i ORDER BY id_instruktora")
    wyplaty
  })
  
  output$historia = renderPrint({
    historia <- dbGetQuery(con, "SELECT * FROM historia ORDER BY czas")
    historia
  })
  
  output$grupa = renderPrint({
    nazwa <- paste0("'", input$taniec, "'")
    query2 <- paste("SELECT * FROM zajecia z LEFT JOIN taniec t USING(id_tanca) 
                     WHERE t.nazwa=", nazwa, 'AND id_grupy=', input$poziom)
    grupa <- dbGetQuery(con, query2)
    grupa
  })
  
  observeEvent(input$payment, {
    dbGetQuery(con,"DELETE FROM wyplaty WHERE True")
    dbGetQuery(con,"SELECT for_wyplaty_instruktorzy()")
  })
  
}

if (interactive()){
  shinyApp(ui = ui, server = server)
}

dbDisconnect(con)
dbUnloadDriver(pg)


