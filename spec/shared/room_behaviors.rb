# frozen_string_literal: true

shared_examples 'room_behavior' do |room_type: nil, query: false|
  let(:server) { RocketChat::Server.new(SERVER_URI) }
  let(:token) { RocketChat::Token.new(authToken: AUTH_TOKEN, userId: USER_ID) }
  let(:session) { RocketChat::Session.new(server, token) }
  let(:scope) { described_class.new(session) }
  let(:room_type) { room_type }
  let(:not_provided_room_body) do
    {
      body: {
        success: false,
        error: 'The parameter "roomId" or "roomName" is required',
        errorType: 'error-roomid-param-not-provided'
      }.to_json,
      status: 400
    }
  end
  let(:invalid_room_message) do
    %(The required "roomId" or "roomName" param provided does not match any #{described_class.field} ) \
      '[error-room-not-found]'
  end
  let(:invalid_room_body) do
    {
      body: {
        success: false,
        error: invalid_room_message,
        errorType: 'error-room-not-found'
      }.to_json,
      status: 400
    }
  end

  describe '#create' do
    before do
      # Stubs for /api/v1/?.create REST API
      stub_unauthed_request :post, described_class.api_path('create')

      stub_authed_request(:post, described_class.api_path('create'))
        .with(
          body: { name: 'duplicate-room' }.to_json
        ).to_return(
          body: {
            success: false,
            error: "A channel with name 'duplicate-room' exists",
            errorType: 'error-duplicate-channel-name'
          }.to_json,
          status: 401
        )

      stub_authed_request(:post, described_class.api_path('create'))
        .with(
          body: { name: 'new-room' }.to_json
        ).to_return(room_response('new-room'))
    end

    context 'with a valid session' do
      it 'returns new room' do
        new_room = scope.create('new-room')
        expect(new_room.id).to eq '1234'
        expect(new_room.name).to eq 'new-room'
        expect(new_room.data['t']).to eq room_type
      end

      context 'with an existing room' do
        it 'raises a status error' do
          expect do
            scope.create('duplicate-room')
          end.to raise_error RocketChat::StatusError, "A channel with name 'duplicate-room' exists"
        end
      end
    end

    context 'with an invalid session token' do
      let(:token) { RocketChat::Token.new(authToken: nil, roomId: nil) }

      it 'raises a status error' do
        expect do
          scope.create('new-room')
        end.to raise_error RocketChat::StatusError, 'You must be logged in to do this.'
      end
    end
  end

  describe '#delete' do
    before do
      # Stubs for /api/v1/?.delete REST API
      stub_unauthed_request :post, described_class.api_path('delete')

      stub_authed_request(:post, described_class.api_path('delete'))
        .to_return(not_provided_room_body)

      stub_authed_request(:post, described_class.api_path('delete'))
        .with(
          body: { roomId: '1236' }
        ).to_return(invalid_room_body)

      stub_authed_request(:post, described_class.api_path('delete'))
        .with(
          body: { roomId: '1234' }.to_json
        ).to_return(
          body: { success: true }.to_json,
          status: 200
        )
    end

    context 'with a valid session' do
      it 'returns success' do
        expect(scope.delete(room_id: '1234')).to be_truthy
      end

      context 'when setting attribute for an invalid room' do
        it 'returns failure' do
          expect(scope.delete(room_id: '1236')).to be false
        end
      end
    end

    context 'with an invalid session token' do
      let(:token) { RocketChat::Token.new(authToken: nil, roomId: nil) }

      it 'raises a status error' do
        expect do
          scope.delete(room_id: '1234')
        end.to raise_error RocketChat::StatusError, 'You must be logged in to do this.'
      end
    end
  end

  describe '#info' do
    before do
      # Stubs for /api/v1/?.info REST API
      stub_unauthed_request :get, described_class.api_path('info?roomId=1234')

      stub_authed_request(:get, described_class.api_path('info?roomId=1236'))
        .to_return(invalid_room_body)

      stub_authed_request(:get, described_class.api_path('info?roomName=invalid-room'))
        .to_return(invalid_room_body)

      stub_authed_request(:get, described_class.api_path('info'))
        .to_return(not_provided_room_body)

      expected = room_response('some-room')

      stub_authed_request(:get, described_class.api_path('info?roomId=1234'))
        .to_return(expected)

      stub_authed_request(:get, described_class.api_path('info?roomName=some-room'))
        .to_return(expected)
    end

    context 'with a valid session' do
      context 'with no room information' do
        it 'raises a status error' do
          expect do
            scope.info(name: nil)
          end.to(
            raise_error(
              RocketChat::StatusError,
              'The parameter "roomId" or "roomName" is required'
            )
          )
        end
      end

      context 'when setting attribute for an invalid room' do
        it 'returns nil' do
          expect(scope.info(room_id: '1236')).to be_nil
          expect(scope.info(name: 'invalid-room')).to be_nil
        end
      end

      context 'when querying an existing roomId' do
        it 'returns room' do
          existing_room = scope.info(room_id: '1234')

          expect(existing_room.id).to eq '1234'
          expect(existing_room.name).to eq 'some-room'
          expect(existing_room.data['t']).to eq room_type
        end
      end

      context 'when querying an existing name' do
        it 'returns room' do
          existing_room = scope.info(name: 'some-room')

          expect(existing_room.id).to eq '1234'
          expect(existing_room.name).to eq 'some-room'
          expect(existing_room.data['t']).to eq room_type
        end
      end
    end

    context 'with an invalid session token' do
      let(:token) { RocketChat::Token.new(authToken: nil, roomId: nil) }

      it 'raises a status error' do
        expect do
          scope.info(room_id: '1234')
        end.to raise_error RocketChat::StatusError, 'You must be logged in to do this.'
      end
    end
  end

  describe '#list' do
    let(:rooms_key) { described_class.collection.to_sym }
    let(:room1) do
      {
        _id: 123,
        name: 'room-one'
      }
    end

    let(:room2) do
      {
        _id: 124,
        name: 'room-two'
      }
    end

    let(:empty_rooms_body) do
      {
        body: {
          success: true,
          rooms_key => []
        }.to_json,
        status: 200
      }
    end

    let(:found_rooms_body) do
      {
        body: {
          success: true,
          rooms_key => [room1]
        }.to_json,
        status: 200
      }
    end

    let(:all_rooms_body) do
      {
        body: {
          success: true,
          rooms_key => [room1, room2]
        }.to_json,
        status: 200
      }
    end

    before do
      # Stubs for /api/v1/rooms.list REST API
      stub_unauthed_request :get, described_class.api_path('list')

      if query
        stub_authed_request(
          :get,
          described_class.api_path('list?query=%7B%22name%22:%22wrong-room%22%7D')
        ).to_return(empty_rooms_body)

        stub_authed_request(
          :get,
          described_class.api_path('list?query=%7B%22name%22:%22room-one%22%7D')
        ).to_return(found_rooms_body)
      end

      stub_authed_request(:get, described_class.api_path('list'))
        .to_return(all_rooms_body)
    end

    context 'with a valid session' do
      if query
        context 'when searching for an invalid room name' do
          it 'is empty' do
            rooms = scope.list(query: { name: 'wrong-room' })

            expect(rooms).to be_empty
          end
        end

        context 'when searching for a valid room name' do
          it 'returns room1' do
            rooms = scope.list(query: { name: 'room-one' })

            expect(rooms.length).to eq 1
            expect(rooms[0].id).to eq 123
            expect(rooms[0].name).to eq 'room-one'
          end
        end
      end

      context 'without a filter' do
        it 'returns all rooms' do
          rooms = scope.list

          expect(rooms.map(&:class)).to eq [RocketChat::Room, RocketChat::Room]
          expect(rooms[0].id).to eq 123
          expect(rooms[0].name).to eq 'room-one'
          expect(rooms[1].id).to eq 124
          expect(rooms[1].name).to eq 'room-two'
        end
      end
    end

    context 'with an invalid session token' do
      let(:token) { RocketChat::Token.new(authToken: nil, groupId: nil) }

      it 'raises a status error' do
        expect do
          scope.list
        end.to raise_error RocketChat::StatusError, 'You must be logged in to do this.'
      end
    end
  end

  describe '#rename' do
    before do
      # Stubs for /api/v1/?.info REST API
      stub_unauthed_request :post, described_class.api_path('rename')

      stub_authed_request(:post, described_class.api_path('rename'))
        .with(
          body: { roomId: 'badId', name: 'new_room_name' }.to_json
        ).to_return(invalid_room_body)

      stub_authed_request(:post, described_class.api_path('rename'))
        .with(
          body: { roomId: nil, name: 'new_room_name' }.to_json
        ).to_return(not_provided_room_body)

      stub_authed_request(:post, described_class.api_path('rename'))
        .with(
          body: { roomId: nil, name: nil }.to_json
        ).to_return(
          body: {
            success: false,
            error: 'The bodyParam "name" is required'
          }.to_json,
          status: 401
        )

      stub_authed_request(:post, described_class.api_path('rename'))
        .with(
          body: { roomId: 'goodId', name: 'new_room_name' }.to_json
        ).to_return(
          body: { success: true }.to_json,
          status: 200
        )
    end

    context 'with a valid session' do
      context 'with no room information' do
        it 'raises a status error' do
          expect do
            scope.rename(nil, 'new_room_name')
          end.to(
            raise_error(
              RocketChat::StatusError,
              'The parameter "roomId" or "roomName" is required'
            )
          )
        end
      end

      context 'when setting attribute for an invalid room' do
        it 'raises a status error' do
          expect do
            scope.rename('badId', 'new_room_name')
          end.to(
            raise_error(RocketChat::StatusError, invalid_room_message)
          )
        end
      end

      context 'with no new name' do
        it 'raises a status error' do
          expect do
            scope.rename(nil, nil)
          end.to(
            raise_error(
              RocketChat::StatusError,
              'The bodyParam "name" is required'
            )
          )
        end
      end

      context 'with all correct parameters' do
        it 'returns success' do
          expect(scope.rename('goodId', 'new_room_name')).to be_truthy
        end
      end
    end

    context 'with an invalid session token' do
      let(:token) { RocketChat::Token.new(authToken: nil, roomId: nil) }

      it 'raises a status error' do
        expect do
          scope.rename('goodId', 'new_room_name')
        end.to raise_error RocketChat::StatusError, 'You must be logged in to do this.'
      end
    end
  end

  describe '#invite' do
    before do
      # Stubs for /api/v1/?.invite REST API
      stub_unauthed_request :post, described_class.api_path('invite')

      stub_authed_request(:post, described_class.api_path('invite'))
        .to_return(not_provided_room_body)

      stub_authed_request(:post, described_class.api_path('invite'))
        .with(
          body: { roomId: '1236', username: 'good-user' }.to_json
        ).to_return(invalid_room_body)

      stub_authed_request(:post, described_class.api_path('invite'))
        .with(
          body: { roomId: '1234', username: 'good-user' }.to_json
        ).to_return(
          body: { success: true }.to_json,
          status: 200
        )
    end

    context 'with a valid session' do
      it 'returns success' do
        expect(scope.invite(room_id: '1234', username: 'good-user')).to be_truthy
      end

      context 'when setting attribute for an invalid room' do
        it 'raises a status error' do
          expect do
            scope.invite(room_id: '1236', username: 'good-user')
          end.to raise_error RocketChat::StatusError, invalid_room_message
        end
      end
    end

    context 'with an invalid session token' do
      let(:token) { RocketChat::Token.new(authToken: nil, roomId: nil) }

      it 'raises a status error' do
        expect do
          scope.invite(room_id: '1234', username: 'good-user')
        end.to raise_error RocketChat::StatusError, 'You must be logged in to do this.'
      end
    end
  end

  describe '#leave' do
    before do
      # Stubs for /api/v1/?.leave REST API
      stub_unauthed_request :post, described_class.api_path('leave')

      stub_authed_request(:post, described_class.api_path('leave'))
        .to_return(not_provided_room_body)

      stub_authed_request(:post, described_class.api_path('leave'))
        .with(
          body: { roomId: '1236' }
        ).to_return(invalid_room_body)

      stub_authed_request(:post, described_class.api_path('leave'))
        .with(
          body: { roomId: '1238' }
        ).to_return(
          body: {
            success: false,
            error: 'You are not in this room [error-user-not-in-room]',
            errorType: 'error-user-not-in-room'
          }.to_json,
          status: 400
        )

      stub_authed_request(:post, described_class.api_path('leave'))
        .with(
          body: { roomId: '1234' }.to_json
        ).to_return(
          body: { success: true }.to_json,
          status: 200
        )
    end

    context 'with a valid session' do
      it 'returns success' do
        expect(scope.leave(room_id: '1234')).to be_truthy
      end

      context 'when setting attribute for an invalid room' do
        it 'raises a status error' do
          expect do
            scope.leave(room_id: '1236')
          end.to raise_error RocketChat::StatusError, invalid_room_message
        end
      end

      context 'when setting attribute for another room' do
        it 'raises a status error' do
          expect do
            scope.leave(room_id: '1238')
          end.to raise_error RocketChat::StatusError, 'You are not in this room [error-user-not-in-room]'
        end
      end
    end

    context 'with an invalid session token' do
      let(:token) { RocketChat::Token.new(authToken: nil, roomId: nil) }

      it 'raises a status error' do
        expect do
          scope.leave(room_id: '1234')
        end.to raise_error RocketChat::StatusError, 'You must be logged in to do this.'
      end
    end
  end

  describe '#members' do
    let(:members_response) do
      {
        body: {
          success: true,
          members: [
            {
              _id: 'rocketID1',
              username: 'rocketUserName1'
            },
            {
              _id: 'rocketID2',
              username: 'rocketUserName2'
            }
          ]
        }.to_json,
        status: 200
      }
    end

    let(:empty_channel_response) do
      {
        body: {
          success: true,
          members: []
        }.to_json,
        status: 200
      }
    end

    let(:invalid_channel_response) do
      {
        body: {
          success: false,
          error: 'Channel does not exists'
        }.to_json,
        status: 400
      }
    end

    before do
      # Stubs for /api/v1/channels.members REST API
      stub_unauthed_request :get, described_class.api_path('members?roomName=authed')

      stub_authed_request(:get, described_class.api_path('members?roomName=wrong-room'))
        .to_return(invalid_channel_response)

      stub_authed_request(:get, described_class.api_path('members?roomName=room-one'))
        .to_return(members_response)

      stub_authed_request(:get, described_class.api_path('members?roomName=empty-room'))
        .to_return(empty_channel_response)
    end

    context 'with an invalid room name' do
      it 'raises a channel existence error' do
        expect do
          scope.members(name: 'wrong-room')
        end.to raise_error RocketChat::StatusError, 'Channel does not exists'
      end
    end

    context 'with a valid room name' do
      it 'returns no users for an empty room' do
        expect(scope.members(name: 'empty-room')).to eq []
      end

      it 'returns online users for a filled room' do
        members = scope.members(name: 'room-one')

        expect(members.map(&:class)).to eq [RocketChat::User, RocketChat::User]
        expect(members[0].id).to eq 'rocketID1'
        expect(members[0].username).to eq 'rocketUserName1'
        expect(members[1].id).to eq 'rocketID2'
        expect(members[1].username).to eq 'rocketUserName2'
      end
    end

    context 'with an invalid session token' do
      let(:token) { RocketChat::Token.new(authToken: nil, groupId: nil) }

      it 'raises an authentication status error' do
        expect do
          scope.members(name: 'authed')
        end.to raise_error RocketChat::StatusError, 'You must be logged in to do this.'
      end
    end
  end

  describe '#set_attr' do
    before do
      # Stubs for /api/v1/?.leave REST API
      stub_unauthed_request :post, described_class.api_path('setTopic')

      stub_authed_request(:post, described_class.api_path('setTopic'))
        .to_return(not_provided_room_body)

      stub_authed_request(:post, described_class.api_path('setTopic'))
        .with(
          body: { roomId: '1236', topic: 'A Topic' }
        ).to_return(invalid_room_body)

      stub_authed_request(:post, described_class.api_path('setTopic'))
        .with(
          body: { roomId: '1238', topic: 'A Topic' }
        ).to_return(
          body: {
            success: false,
            error: 'You are not in this room [error-user-not-in-room]',
            errorType: 'error-user-not-in-room'
          }.to_json,
          status: 400
        )

      stub_authed_request(:post, described_class.api_path('setTopic'))
        .with(
          body: { roomId: '1234', topic: 'A Topic' }
        ).to_return(
          body: { success: true }.to_json,
          status: 200
        )
    end

    context 'when trying to set an invalid attribute' do
      it 'raises an argument error' do
        expect do
          scope.set_attr(room_id: '1234', bad_attr: true)
        end.to raise_error ArgumentError
      end
    end

    context 'with a valid session' do
      it 'returns success' do
        expect(scope.set_attr(room_id: '1234', topic: 'A Topic')).to be_truthy
      end

      context 'when setting attribute for an invalid room' do
        it 'raises a status error' do
          expect do
            scope.set_attr(room_id: '1236', topic: 'A Topic')
          end.to raise_error RocketChat::StatusError, invalid_room_message
        end
      end

      context 'when setting attribute for another room' do
        it 'raises a status error' do
          expect do
            scope.set_attr(room_id: '1238', topic: 'A Topic')
          end.to raise_error RocketChat::StatusError, 'You are not in this room [error-user-not-in-room]'
        end
      end
    end

    context 'with an invalid session token' do
      let(:token) { RocketChat::Token.new(authToken: nil, roomId: nil) }

      it 'raises a status error' do
        expect do
          scope.set_attr(room_id: '1234', topic: 'A Topic')
        end.to raise_error RocketChat::StatusError, 'You must be logged in to do this.'
      end
    end
  end

  ### Room request/response helpers

  def room_response(name)
    {
      body: {
        success: true,
        described_class.name.split('::')[-1].downcase => {
          _id: '1234',
          name: name,
          t: room_type
        }
      }.to_json,
      status: 200
    }
  end
end
