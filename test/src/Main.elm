port module Main exposing (..)

port reportTestResult : TestResult -> Cmd msg
port start : (String -> msg) -> Sub msg

type alias TestResult = { description : String, pass : Bool, details : String }

main : Program String Model Msg
main = Platform.worker
  { init = init
  , update = update
  , subscriptions = subscriptions
  }

type Msg
  = Start String

type alias Model = { }

init : String -> ( Model, Cmd Msg )
init _ = ( { }, Cmd.none )

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model = 
  case msg of
    Start _ -> ( model, TestResult "test1" True "" |> reportTestResult )

subscriptions : Model -> Sub Msg
subscriptions _ = start Start
