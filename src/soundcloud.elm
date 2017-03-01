port module Main exposing (..)

import Html exposing (..)
import Html.Attributes as Attr exposing (..)
import Html.Events exposing (..)
import Http
import Json.Decode as Decode exposing (Decoder, decodeString, field, map, oneOf, string, int, float, at, null)
import Time exposing (..)
import Date
import Date.Format exposing (format)


client_id : String
client_id =
    "eb6df903547f8123e3cb79e5429a0999"


port playSong : String -> Cmd msg


port pauseSong : String -> Cmd msg


port stopSong : String -> Cmd msg


port seekSong : Time -> Cmd msg


port endSong : (() -> msg) -> Sub msg


onChange : (Time -> msg) -> Attribute msg
onChange toMsg =
    at [ "target", "value" ] string
        |> Decode.map (String.toInt >> Result.withDefault 0 >> toFloat >> toMsg)
        |> on "change"


main : Program Never Model Msg
main =
    Html.program
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }



-- MODEL


type alias Model =
    { query : String
    , songs : List Song
    , current_song : Maybe Song
    , is_playing : Bool
    , elapsed_time : Time
    , playlist : List Song
    }


type alias Song =
    { id : Int
    , title : String
    , artwork_url : Maybe String
    , duration : Time
    , stream_url : String
    }


init : ( Model, Cmd Msg )
init =
    ( Model "" [] Nothing False 0 []
    , Cmd.none
    )



-- UPDATE


type Msg
    = Search String
    | Change String
    | Play Song
    | Stop
    | Pause
    | Seek Time
    | PlayNext
    | SongList (Result Http.Error (List Song))
    | Tick
    | AddToPlaylist Song


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Search query ->
            ( model, getSongs query )

        Change input ->
            ( { model | query = input }, Cmd.none )

        Play song ->
            let
                time =
                    if (Just song /= model.current_song) then
                        0
                    else
                        model.elapsed_time
            in
                ( { model | current_song = Just song, is_playing = True, elapsed_time = time }
                , playSong (song.stream_url ++ "?client_id=" ++ client_id)
                )

        PlayNext ->
            case model.playlist of
                song :: list ->
                    update (Play song) { model | playlist = list }

                _ ->
                    update Stop model

        Pause ->
            ( { model | is_playing = False }, pauseSong "" )

        Stop ->
            ( { model | current_song = Nothing, is_playing = False, elapsed_time = 0 }, stopSong "" )

        Seek time ->
            ( { model | elapsed_time = time }, seekSong time )

        SongList (Ok songs) ->
            ( { model | songs = songs }, Cmd.none )

        SongList (Err _) ->
            ( model, Cmd.none )

        AddToPlaylist song ->
            ( { model | playlist = song :: model.playlist }, Cmd.none )

        Tick ->
            let
                new_time : Time
                new_time =
                    ((+) second) model.elapsed_time
            in
                ( { model | elapsed_time = new_time }, Cmd.none )



-- VIEW


view : Model -> Html Msg
view model =
    div []
        [ h2 [] [ text "Search a song:" ]
        , Html.form [ onSubmit (Search model.query) ]
            [ input [ type_ "text", placeholder "some song...", value model.query, onInput Change ] []
            , button [ type_ "submit" ] [ text "Search" ]
            , audio [] []
            ]
        , br [] []
        , renderPlayingSong model.is_playing model.elapsed_time model.current_song
        , br [] []
        , renderSongs model.songs
        , h3 [] [ text "Playlist" ]
        , renderSongs model.playlist
        ]


renderPlayingSong : Bool -> Time -> Maybe Song -> Html Msg
renderPlayingSong is_playing elapsed_time playing =
    let
        displayFormat time =
            time
                |> Date.fromTime
                |> format "%M:%S"

        cover url =
            case url of
                Just img_src ->
                    img [ src img_src ] []

                _ ->
                    text ""
    in
        case playing of
            Just song ->
                div []
                    [ cover song.artwork_url
                    , h3 [] [ text ("Playing: " ++ song.title) ]
                    , p [] [ text (displayFormat elapsed_time ++ "/" ++ displayFormat song.duration) ]
                    , div []
                        [ if is_playing then
                            button [ onClick Pause ] [ text "Pause" ]
                          else
                            button [ onClick (Play song) ] [ text "Play" ]
                        , button [ onClick Stop ] [ text "Stop" ]
                        , button [ onClick PlayNext ] [ text "Next" ]
                        ]
                    , input [ type_ "range", onChange Seek, Attr.max (toString song.duration), value (toString elapsed_time) ] []
                    ]

            Nothing ->
                text ""


renderSongs : List Song -> Html Msg
renderSongs songs =
    songs
        |> List.map
            (\song ->
                ([ a [ href "#", onClick <| Play song ] [ text song.title ]
                 , button [ onClick <| AddToPlaylist song ] [ text "add To playlist" ]
                 ]
                )
            )
        |> List.map (li [])
        |> (ul [])



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ if (model.is_playing) then
            every second <| always Tick
          else
            Sub.none
        , endSong (always PlayNext)
        ]



-- HTTP


getSongs : String -> Cmd Msg
getSongs query =
    let
        limit =
            toString 50

        url =
            "http://api.soundcloud.com/tracks?client_id=" ++ client_id ++ "&limit=" ++ limit ++ "&q=" ++ query
    in
        Http.send SongList (Http.get url decodeSongs)


decodeSongs : Decoder (List Song)
decodeSongs =
    Decode.list
        (Decode.map5 Song
            (field "id" int)
            (field "title" string)
            (field "artwork_url" (oneOf [ Decode.map Just string, null Nothing ]))
            (field "duration" float)
            (field "stream_url" string)
        )
