class Client < Snake
  include Celluloid
  include Celluloid::Notifications
  include Celluloid::Logger
  
  attr_accessor :tournament
  attr_reader :socket, :id, :first_name, :last_name, :image_url, :wins, :losses, :guest

  trap_exit :actor_died

  def initialize(socket)
    info "Binding socket to client"
    @socket = socket
    listener = SocketListener.new(Actor.current, socket, :on_message)
    super
  end

  def actor_died(actor, reason)
    info "Terminating due to socket listener failure"
    terminate
  end

  def on_message(data)
    message = MultiJson.load data
    
    case message["type"]
    when "chat_message"
      msg = MultiJson.dump({
        'type' => 'chat_message',
        'id'   => id,
        'name' => first_name,
        'image_url' => image_url,
        'message' => message["value"]
      })

      tournament.clients.each { |c| c.transmit(msg) }
    when "identify"
      decrypted_id = User.decrypt_id(message["value"])
      if decrypted_id.start_with?('guest')
        @id = decrypted_id.to_s
        @first_name = "Guest " + decrypted_id.split('-').last[0..4]
        @last_name = ""
        @image_url = "http://www.gravatar.com/avatar/#{Digest::MD5.hexdigest(@id)}.png?d=identicon&s=50"
        @wins = 0
        @losses = 0
        @guest = true
      else
        user = User.find(decrypted_id)
        @id = user.id.to_s
        @first_name = user.first_name
        @last_name = user.last_name
        @image_url = user.image_url
        @wins = user.wins
        @losses = user.losses
        @guest = false
      end
      
      async.publish('tournament_request', Actor.current)
    when "direction"
      dir = message["value"]
      @direction = Direction[dir] if valid_direction?(dir)
    end
  end

  # def identify
  #   transmit MultiJson.dump({ 'type' => 'identify', 'value' => { 'id' => id } })
  # end

  def browser_hash
    {
      id: id,
      first_name: first_name,
      last_name: last_name,
      image_url: image_url,
      apples: apples,
      wins: wins,
      losses: losses
    }
  end

  def update_map(map)
    transmit MultiJson.dump({ 'type' => 'map', 'value' => map })
  end

  def server_message(msg)
    transmit MultiJson.dump({ 'type' => 'chat_message', id: 0, name: 'Server', message: msg})
  end

  def broadcast_participants(clients)
    transmit MultiJson.dump({ 'type' => 'participants', 'value' => clients.map(&:browser_hash) })
  end

  def ping
    transmit MultiJson.dump({ 'type' => 'ping', 'value' => nil })
  end

  def add_loss
    if !guest
      user = User.find(@id)
      user.losses += 1
      user.save
    end
  end

  def add_win
    if !guest
      user = User.find(@id)
      user.wins += 1
      user.save
    end
  end

  def transmit(msg)
    @socket << msg
  rescue Reel::SocketError
    info "Time client disconnected"
    terminate
  end

  def to_s
    s = first_name
    s += " (#{wins} - #{losses})" unless guest
    s
  end

end
