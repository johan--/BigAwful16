class Game < ApplicationRecord
  serialize :definition
  has_one :grandpa, dependent: :destroy
  has_one :grandson, dependent: :destroy
  has_one :translator, dependent: :destroy
  belongs_to :high_score, optional:true
  has_many :messages

  before_create(:add_translator)
  before_create(:add_high_score)

  default_scope { order('created_at') }

  def self.needs_grandpas
    Game.all.select{|g| g.grandpa.nil? && g.grandson.present?}
  end

  def self.needs_grandsons
    Game.all.select{|g| g.grandson.nil? && g.grandpa.present?}
  end

  def self.join_or_create(user)
    if(user.class == Grandpa)
      games = Game.needs_grandpas
      if(games.empty?)
        game = Game.create!(grandpa: user)
        ActionCable.server.broadcast "menu", action: "incrementAvailableGrandpas"
      else
        game = games.first
        game.grandpa = user
        game.save!
        ActionCable.server.broadcast "menu", action: "decrementAvailableGrandsons"
      end
    elsif(user.class == Grandson)
      games = Game.needs_grandsons
      if(games.empty?)
        game = Game.create!(grandson: user)
        ActionCable.server.broadcast "menu", action: "incrementAvailableGrandsons"
      else
        game = games.first
        game.grandson = user
        game.save!
        ActionCable.server.broadcast "menu", action: "decrementAvailableGrandpas"
      end
    else
      raise "You done fucked up."
    end
    game
  end

  def send_message(user, commands)
    if(commands.empty?)
      commands = ["Well, I mean... I dunno. Nevermind."]
    end
    message = "<span class='speaker'>#{user.type}</span> #{translator.translate(user, commands)}"
    ActionCable.server.broadcast "game_#{id}",
      action: "message",
      message: message
  end

  def start
    self.definition = generate_definition
    save!
    ActionCable.server.broadcast "game_#{id}",
        action: 'startClient',
        message: definition

    # Messages to Grandson
    ActionCable.server.broadcast "player_#{grandson.cid}",
      action: 'message',
      message: "The phone rings. You answer it."
    ActionCable.server.broadcast "player_#{grandson.cid}",
      action: 'message',
      message: "oh no it's grandpa"
    ActionCable.server.broadcast "player_#{grandson.cid}",
      action: 'updateStatus',
      message: "Providing Tech Support"

    # Messages to Grandpa
    ActionCable.server.broadcast "player_#{grandpa.cid}",
      action: 'message',
      message: "Your grandson picks up the phone."
    ActionCable.server.broadcast "player_#{grandpa.cid}",
      action: 'updateStatus',
      message: "Receiving Help"

    self.high_score.start_time = Time.now
    self.high_score.save!
  end

  def generate_definition
    @number_of_towers = case self.grandson.difficulty
      when 0
        1
      when 1
        3
      else
        4
    end
    @number_of_monitors = case self.grandson.difficulty
      when 0
        1
      when 1
        2
      else
        3
    end
    monitors = generate_monitors
    towers = generate_towers
    definition = {
      grandpasHardware: { monitor: rand(@number_of_monitors), tower: rand(@number_of_towers) },
      monitors: monitors,
      towers: towers
    }
    definition
  end

  def generate_monitors
    monitors = []
    shuffabit = lambda{('a'..'z').to_a.shuffle}
    @possible_monitor_names = [
      "#{shuffabit.call.first(3).join}-#{rand(500).to_s}#{shuffabit.call.first(2).join}",
      "#{shuffabit.call.first(3).join}#{rand(500).to_s}",
      "#{shuffabit.call.first(2).join}-#{shuffabit.call.first}#{rand(2000).to_s}",
      "#{shuffabit.call.first(1).join}-#{rand(500).to_s}#{shuffabit.call.first(2).join}",
      "#{shuffabit.call.first(5).join}#{rand(99).to_s}",
      "#{shuffabit.call.first(2).join}-#{shuffabit.call.first}#{rand(20).to_s}"
    ].shuffle
    (@number_of_monitors).times do
      @possible_cable_colors = ['blue', 'green', 'red'].shuffle
      monitors << generate_monitor
    end
    monitors
  end

  def generate_monitor
    monitor = {
      name: generate_monitor_name,
      type: ['XVD', 'SGA'].sample,
      logo: rand(10),
      monitorButtons: generate_monitor_buttons,
      monitorCables: {
        power: @possible_cable_colors.pop,
        data: @possible_cable_colors.pop
      },
      monitorInput: rand(4)
    }
    monitor
  end

  def generate_monitor_name
    @possible_monitor_names.pop
  end

  def generate_monitor_buttons
    buttons = [0,0,0,0,0,0,0,0,0,0,0,0]
    slots = [0,1,2,3,4,5,6,7,8,9,10,11].shuffle
    # 12 possible button slots, 4 possible unique non-zero values:
    # 0: empty, 1: power, 2: input, 3: degauss, 4: nothing
    [1,2,3,4].each do |n|
      index = slots.pop
      buttons[index] = n
    end
    buttons
  end

  def generate_towers
    monitors = []
    @possible_tower_names = [
        "Super-1",
        "Grinder XT",
        "EVO GT",
        "MEGADeck ST4",
        "Nintendo Entertainment Tower",
        "Loggerback LAN Master",
        "Fidelus Maximus GV1.23",
        "ST2 W3 FIREMAKER",
        "Official Generic Brand Tower",
        "AOL Advanced w/ Intel Dual Core Technology",
        "Boxbrand Cheapo v4",
        "Exvadius 1998XT"
    ].shuffle
    @number_of_towers.times do
      @possible_cable_colors = ['yellow', 'purple'].shuffle
      monitors << generate_tower
    end
    monitors
  end

  def generate_tower
    {
      name: @possible_tower_names.pop,
      logo: rand(4),
      towerPort: rand(4),
      towerCable: @possible_cable_colors.pop,
      roundButtons: [rand(3), rand(3)],
      squareButtons: [rand(3), rand(3)],
      towerSwitches: { powerOn: ['left','right'].sample, monitorXVD: ['left','right'].sample }
    }
  end
  
  def win
    self.high_score.end_time = Time.now
    self.high_score.status = "won"
    self.high_score.save!
    ActionCable.server.broadcast "player_#{grandson.cid}",
      action: 'win'
    ActionCable.server.broadcast "game_#{id}",
      action: 'message',
      message: "Grandpa has successfully turned on his computer. The game is over. This game took #{high_score.formatted_duration}, and your unique game score identifier is '#{high_score.id}'"
    ActionCable.server.broadcast "player_#{grandpa.cid}",
      action: 'updateStatus',
      message: "Finally getting things done"
    ActionCable.server.broadcast "player_#{grandson.cid}",
      action: 'updateStatus',
      message: "Enjoying yourself"
  end

  def lose
    self.high_score.end_time = Time.now
    self.high_score.status = "lost"
    self.high_score.save!
    ActionCable.server.broadcast "player_#{grandson.cid}",
      action: 'lose'
    ActionCable.server.broadcast "game_#{id}",
      action: 'message',
      message: "Grandpa has given up. The game is over. This game took #{high_score.formatted_duration}, and your unique game score identifier is '#{high_score.id}'"
    ActionCable.server.broadcast "player_#{grandpa.cid}",
      action: 'updateStatus',
      message: "Finally getting things done"
    ActionCable.server.broadcast "player_#{grandson.cid}",
      action: 'updateStatus',
      message: "Enjoying yourself"
  end
private
  def add_translator
    self.translator = Translator.create!
  end

  def add_high_score
    self.high_score = HighScore.create!
  end
end
