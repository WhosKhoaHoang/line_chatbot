# app.rb
require "sinatra"
require "json"
require "net/http"
require "uri"
require "tempfile"

require "line/bot"
require "ibm_watson/visual_recognition_v3"

include IBMWatson


def client
  @client ||= Line::Bot::Client.new { |config|
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_ACCESS_TOKEN"]
  }
end


# TODO:
# - Figure out why an initial call to the
#   ArnoldBotAPI takea so long...
# - Find a better way to test this module
def bot_answer_to(a_question, user_name)
  uri = URI("https://arnoldbot-api.herokuapp.com/talk?msg="+a_question)
  resp = Net::HTTP.get(uri)
  return JSON.load(resp)["response"]
end


def bot_jp_answer_to(a_question, user_name)
  if a_question.match?(/(おはよう|こんにちは|こんばんは|ヤッホー|ハロー).*/)
    "こんにちは#{user_name}さん！お元気ですか?"
  elsif a_question.match?(/.*元気.*(？|\?｜か)/)
    "私は元気です、#{user_name}さん"
  elsif a_question.match?(/.*(le wagon|ワゴン|バゴン).*/i)
    "#{user_name}さん... もしかして京都のLE WAGONプログラミング学校の話ですかね？ 素敵な画っこと思います！"
  elsif a_question.end_with?('?','？')
    "いい質問ですね、#{user_name}さん！"
  else
    ["そうですね！", "確かに！", "間違い無いですね！"].sample
  end
end


post "/callback" do
  body = request.body.read

  signature = request.env["HTTP_X_LINE_SIGNATURE"]
  unless client.validate_signature(body, signature)
    error 400 do "Bad Request" end
  end

  events = client.parse_events_from(body)
  events.each { |event|
    case event
    # Text recognition using REGEX and vanilla Ruby
    when Line::Bot::Event::Message
      case event.type
      when Line::Bot::Event::MessageType::Text
        p event
        user_id = event["source"]["userId"]
        user_name = ""

        response = client.get_profile(user_id)
        case response
        when Net::HTTPSuccess then
          contact = JSON.parse(response.body)
          p contact
          user_name = contact["displayName"]
        else
          p "#{response.code} #{response.body}"
        end

        # The answer mecanism is here!
        message = {
          type: "text",
          text: bot_answer_to(event.message["text"], user_name)
        }
        client.reply_message(event["replyToken"], message)

        p 'One more message!'
        p event["replyToken"]
        p message
        p client

      # Image recognition
      when Line::Bot::Event::MessageType::Image
        response_image = client.get_message_content(event.message["id"])
        tf = Tempfile.open
        tf.write(response_image.body)

        # Using IBM Watson visual recognition API
        visual_recognition = VisualRecognitionV3.new(
          version: "2018-03-19",
          iam_apikey: ENV["IBM_IAM_API_KEY"]
        )

        image_result = ""
        File.open(tf.path) do |images_file|
          classes = visual_recognition.classify(
            images_file: images_file,
            threshold: "0.6"
          )
          image_result = p classes.result["images"][0]["classifiers"][0]["classes"]
        end
        # # Sending the results
        message = {
          type: "text",
          text: "I think it reminds me of a #{image_result[0]["class"].capitalize} thing or maybe... #{image_result[1]["class"].capitalize}?? or some words like that... let say #{image_result[2]["class"].capitalize}, am I right?"
        }

        client.reply_message(event["replyToken"], message)
        tf.unlink
      end
    end
  }

  "OK"
end


# puts "\n\n"
# puts bot_answer_to("hello", "test")
# puts "\n\n"
