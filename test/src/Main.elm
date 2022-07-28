port module Main exposing (..)

import Dict exposing (Dict)
import Task
import TaskPort exposing (Result, Error, JSError, JSErrorRecord)
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
  | Case1 String (Result (List String))
  | Case2 String (Result (List String))
  | Case3 String (Result (Dict String String))
  | Case4 String (Result String)
  | Case5 String (Result String)
  | Case6 String (Result String)
  | Case7 String (Result String)
  | Case8 String (Result String)
  | Case9 String (Result String)
  | Case10 String (Result String)
  | Case11 String (Result String)

type alias Model = { }

init : String -> ( Model, Cmd Msg )
init _ = ( { }, Cmd.none )

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model = 
  ( model
  , case {-- Debug.log "handling msg" --} msg of
      Start _ -> TaskPort.call { function = "echo", valueDecoder = JD.list JD.string, argsEncoder = JE.list JE.string } [ "echo1", "echo2" ] |> Task.attempt (Case1 "test1")

      Case1 testId res ->
        [ expect testId (ppList ppString) [ "echo1", "echo2" ] res |> reportTestResult
        , TaskPort.callNoArgs { function = "noArgs2", valueDecoder = JD.list JD.string } |> Task.attempt (Case2 "test2")
        ] |> Cmd.batch

      Case2 testId res ->
        [ expect testId (ppList ppString) [ "value1", "value2" ] res |> reportTestResult
        , TaskPort.callNoArgs { function = "noArgs3", valueDecoder = JD.dict JD.string } |> Task.attempt (Case3 "test3")
        ] |> Cmd.batch

      Case3 testId res ->
        [ expect testId (ppDict ppString ppString) (Dict.fromList [ ( "key1", "value1" ), ( "key2", "value2" ) ]) res |> reportTestResult
        , TaskPort.callNoArgs { function = "notRegistered", valueDecoder = JD.string } |> Task.attempt (Case4 "test4")
        ] |> Cmd.batch

      Case4 testId res ->
        [ expectInteropError testId (TaskPort.NotFound "notRegistered") res |> reportTestResult
        , TaskPort.callNoArgs { function = "noArgsAsyncResolve", valueDecoder = JD.string } |> Task.attempt (Case5 "test5")
        ] |> Cmd.batch

      Case5 testId res ->
        [ expect testId identity "success" res |> reportTestResult
        , TaskPort.callNoArgs { function = "noArgsAsyncReject", valueDecoder = JD.string } |> Task.attempt (Case6 "test6")
        ] |> Cmd.batch

      Case6 testId res ->
        [ expectJSError testId (TaskPort.ErrorValue (JE.string "expected")) res |> reportTestResult
        , TaskPort.callNoArgs { function = "noArgsThrowsError", valueDecoder = JD.string } |> Task.attempt (Case7 "test7")
        ] |> Cmd.batch

      Case7 testId res ->
        [ expectJSError testId (makeJSError "Error" "expected") res |> reportTestResult
        , TaskPort.callNoArgs { function = "noArgsThrowsErrorWithNestedError", valueDecoder = JD.string } |> Task.attempt (Case8 "test8")
        ] |> Cmd.batch

      Case8 testId res ->
        [ expectJSError testId (makeJSErrorWithACause "Error" "expected" (makeJSError "Error" "nested")) res |> reportTestResult
        , TaskPort.callNS
            { function = "echo" |> TaskPort.inNamespace "test/test" "123"
            , valueDecoder = JD.string
            , argsEncoder = JE.string
            }
            "hello"
            |> Task.attempt (Case9 "test9")
        ] |> Cmd.batch

      Case9 testId res ->
        [ expect testId identity "hello" res |> reportTestResult
        , TaskPort.callNoArgsNS
            { function = "notRegistered" |> TaskPort.inNamespace "test/test" "123"
            , valueDecoder = JD.string
            }
            |> Task.attempt (Case10 "test10")
        ] |> Cmd.batch

      Case10 testId res ->
        [ expectInteropError testId (TaskPort.NotFound "test/test/notRegistered") res |> reportTestResult
        , TaskPort.callNoArgsNS
            { function = "echo" |> TaskPort.inNamespace "test/test" "321"
            , valueDecoder = JD.string
            }
            |> Task.attempt (Case11 "test11")
        ] |> Cmd.batch

      Case11 testId res ->
        [ expectInteropError testId (TaskPort.NotCompatible "test/test/echo") res |> reportTestResult
        , completed "OK"
        ] |> Cmd.batch
  )

makeJSError name message = TaskPort.ErrorObject name (JSErrorRecord name message [] Nothing)
makeJSErrorWithACause name message cause = TaskPort.ErrorObject name (JSErrorRecord name message [] (Just cause))

ppString : String -> String
ppString str = "\"" ++ str ++ "\""

ppList : (item -> String) -> List item -> String
ppList ppItem list = "[ " ++ String.join ", " (List.map ppItem list) ++ " ]"

ppDict : (key -> String) -> (value -> String) -> Dict key value -> String
ppDict ppKey ppValue dict = "{ " ++ String.join ", " (List.map (\( k, v ) -> ppKey k ++ ":" ++ ppValue v) (Dict.toList dict)) ++ " }"

expect : String -> (value -> String) -> value -> Result value -> TestResult
expect testId valuePrinter expectedValue result =
  case {-- Debug.log "received result" --} result of
    Result.Ok actualValue ->
      if (actualValue == expectedValue) then
        TestResult testId True ""
      else
        TestResult testId False <| "Actual: " ++ (valuePrinter actualValue)
    
    Result.Err err ->
      TestResult testId False <| TaskPort.errorToString err

expectJSError : String -> JSError -> Result value -> TestResult
expectJSError testId expectedError result =
  case result of
    Result.Ok actualValue -> TestResult testId False "Expected JS call error"
    
    Result.Err (TaskPort.InteropError err) ->
      TestResult testId False (TaskPort.interopErrorToString err)
    
    Result.Err (TaskPort.JSError err) ->
      if (compareJSErrors expectedError err) then
        TestResult testId True ""
      else
        TestResult testId False ("Expected JS error:\n" ++ (jsErrorToString expectedError) ++ "Actual JS error:\n" ++ (jsErrorToString err))

compareJSErrors : JSError -> JSError -> Bool
compareJSErrors expected actual =
  case ( expected, actual ) of
    ( TaskPort.ErrorValue e, TaskPort.ErrorValue a ) -> e == a
    ( TaskPort.ErrorObject expectedName e, TaskPort.ErrorObject actualName a ) ->
      if (expectedName == actualName && e.message == a.message) then
        case ( e.cause, a.cause ) of
          ( Nothing, Nothing ) -> True
          ( Just expectedCause, Just actualCause ) -> compareJSErrors expectedCause actualCause
          _ -> False -- one has a cause, and one doesn't
      else
        False

    _ -> False -- different payload types

expectInteropError : String -> TaskPort.InteropError -> Result value -> TestResult
expectInteropError testId expectedError result =
  case result of
    Result.Err (TaskPort.InteropError err) ->
      if (err == expectedError) then
        TestResult testId True ""
      else
        TestResult testId False ("Expected different error.\nExpected: " ++ TaskPort.interopErrorToString expectedError ++ "\nGot: " ++ TaskPort.interopErrorToString err)

    Result.Err (TaskPort.JSError err) -> TestResult testId False ("Expected interop error, got JSError.\n" ++ jsErrorToString err)
    Result.Ok ok -> TestResult testId False "Expected error"

jsErrorToString : JSError -> String
jsErrorToString jse = TaskPort.errorToString (TaskPort.JSError jse)

subscriptions : Model -> Sub Msg
subscriptions _ = start Start
