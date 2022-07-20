port module Main exposing (..)

import Dict exposing (Dict)
import Task
import TaskPort
import Json.Encode as JE
import Json.Decode as JD

port reportTestResult : TestResult -> Cmd msg
port completed : String -> Cmd msg
port start : (String -> msg) -> Sub msg

type alias TestResult = { testId : String, pass : Bool, details : String }

main : Program String Model Msg
main = Platform.worker
  { init = init
  , update = update
  , subscriptions = subscriptions
  }

type Msg
  = Start String
  | Case1 String (Result (TaskPort.Error String) String)
  | Case2 String (Result (TaskPort.Error String) (List String))
  | Case3 String (Result (TaskPort.Error String) (Dict String String))
  | Case4 String (Result (TaskPort.Error String) String)
  | Case5 String (Result (TaskPort.Error String) String)
  | Case6 String (Result (TaskPort.Error String) String)
  | Case7 String (Result (TaskPort.Error String) String)

type alias Model = { }

init : String -> ( Model, Cmd Msg )
init _ = ( { }, Cmd.none )

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model = 
  ( model
  , case {-- Debug.log "handling msg" --} msg of
      Start _ -> TaskPort.callNoArgs "noArgs" JD.string JD.string |> Task.attempt (Case1 "test1")
      Case1 testId res ->
        [ expect testId identity identity "string value" res |> reportTestResult
        , TaskPort.callNoArgs "noArgs2" (JD.list JD.string) JD.string |> Task.attempt (Case2 "test2")
        ] |> Cmd.batch
      Case2 testId res ->
        [ expect testId (ppList ppString) identity [ "value1", "value2" ] res |> reportTestResult
        , TaskPort.callNoArgs "noArgs3" (JD.dict JD.string) JD.string |> Task.attempt (Case3 "test3")
        ] |> Cmd.batch

      Case3 testId res ->
        [ expect testId (ppDict ppString ppString) identity (Dict.fromList [ ( "key1", "value1" ), ( "key2", "value2" ) ]) res |> reportTestResult
        , TaskPort.callNoArgs "notRegistered" JD.string JD.string |> Task.attempt (Case4 "test4")
        ] |> Cmd.batch

      Case4 testId res ->
        [ expectInteropError testId TaskPort.FunctionNotFound res |> reportTestResult
        , TaskPort.callNoArgs "noArgsAsyncResolve" JD.string JD.string |> Task.attempt (Case5 "test5")
        ] |> Cmd.batch

      Case5 testId res ->
        [ expect testId identity identity "success" res |> reportTestResult
        , TaskPort.callNoArgs "noArgsAsyncReject" JD.string JD.string |> Task.attempt (Case6 "test6")
        ] |> Cmd.batch

      Case6 testId res ->
        [ expectCallError testId identity "expected" res |> reportTestResult
        , TaskPort.callNoArgs "noArgsThrowsError" JD.string JD.string |> Task.attempt (Case7 "test7")
        ] |> Cmd.batch

      Case7 testId res ->
        [ expectCallError testId identity "expected" res |> reportTestResult
        , completed "OK"
        ] |> Cmd.batch
  )

ppString : String -> String
ppString str = "\"" ++ str ++ "\""

ppList : (item -> String) -> List item -> String
ppList ppItem list = "[ " ++ String.join ", " (List.map ppItem list) ++ " ]"

ppDict : (key -> String) -> (value -> String) -> Dict key value -> String
ppDict ppKey ppValue dict = "{ " ++ String.join ", " (List.map (\( k, v ) -> ppKey k ++ ":" ++ ppValue v) (Dict.toList dict)) ++ " }"

expect : String -> (value -> String) -> (error -> String) -> value -> Result (TaskPort.Error error) value -> TestResult
expect testId valuePrinter errorPrinter expectedValue result =
  case {-- Debug.log "received result" --} result of
    Result.Ok actualValue ->
      if (actualValue == expectedValue) then
        TestResult testId True ""
      else
        TestResult testId False <| "Actual: " ++ (valuePrinter actualValue)
    
    Result.Err (TaskPort.InteropError err) ->
      TestResult testId False (TaskPort.interopErrorToString err)
    
    Result.Err (TaskPort.CallError error) ->
      TestResult testId False <| "CallError: " ++ errorPrinter error

expectCallError : String -> (error -> String) -> error -> Result (TaskPort.Error error) value -> TestResult
expectCallError testId errorPrinter expectedError result =
  case result of
    Result.Ok actualValue -> TestResult testId False "Expected error"
    
    Result.Err (TaskPort.InteropError err) ->
      TestResult testId False (TaskPort.interopErrorToString err)
    
    Result.Err (TaskPort.CallError error) ->
      if (error == expectedError) then
        TestResult testId True ""
      else
        TestResult testId False ("CallError: " ++ errorPrinter error)

expectInteropError : String -> TaskPort.InteropError -> Result (TaskPort.Error error) value -> TestResult
expectInteropError testId expectedError result =
  case result of
    Result.Err (TaskPort.InteropError err) ->
      if (err == expectedError) then
        TestResult testId True ""
      else
        TestResult testId False ("Expected different error.\nExpected: " ++ TaskPort.interopErrorToString expectedError ++ "\nGot: " ++ TaskPort.interopErrorToString err)

    Result.Err (TaskPort.CallError _) -> TestResult testId False "Expected interop error"
    Result.Ok ok -> TestResult testId False "Expected error"

subscriptions : Model -> Sub Msg
subscriptions _ = start Start
