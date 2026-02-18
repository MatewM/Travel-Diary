require "rails_helper"

RSpec.describe "Tickets", type: :request do
  let(:user) { create(:user) }

  let(:valid_pdf) do
    Rack::Test::UploadedFile.new(
      Rails.root.join("spec/fixtures/files/sample.pdf"),
      "application/pdf"
    )
  end

  let(:valid_jpg) do
    Rack::Test::UploadedFile.new(
      Rails.root.join("spec/fixtures/files/sample.jpg"),
      "image/jpeg"
    )
  end

  let(:oversized_file) do
    content = "x" * (11 * 1024 * 1024)
    file = Tempfile.new([ "oversized", ".pdf" ])
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file, "application/pdf")
  end

  let(:invalid_type_file) do
    Rack::Test::UploadedFile.new(
      Rails.root.join("spec/fixtures/files/sample.exe"),
      "application/octet-stream"
    )
  end

  describe "POST /tickets" do
    context "usuario autenticado" do
      before { sign_in(user) }

      it "crea un ticket por cada archivo — un PDF genera 1 ticket" do
        expect {
          post tickets_path, params: { ticket: { original_files: [ valid_pdf ] } }
        }.to change(Ticket, :count).by(1)

        ticket = Ticket.last
        expect(ticket.user).to eq(user)
        expect(ticket.status).to eq("pending_parse")
        expect(ticket.trip).to be_nil
        expect(ticket.original_files).to be_attached
      end

      it "crea un ticket por cada archivo — dos archivos generan 2 tickets" do
        expect {
          post tickets_path, params: { ticket: { original_files: [ valid_pdf, valid_jpg ] } }
        }.to change(Ticket, :count).by(2)
      end

      it "crea un ticket al subir una imagen JPG válida" do
        expect {
          post tickets_path, params: { ticket: { original_files: [ valid_jpg ] } }
        }.to change(Ticket, :count).by(1)
      end

      it "responde con turbo stream en creación exitosa" do
        post tickets_path,
             params: { ticket: { original_files: [ valid_pdf ] } },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end

      it "falla y no crea ticket si no se sube ningún archivo" do
        expect {
          post tickets_path, params: { ticket: {} }
        }.not_to change(Ticket, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "no crea ticket si el único archivo supera los 10MB" do
        expect {
          post tickets_path, params: { ticket: { original_files: [ oversized_file ] } }
        }.not_to change(Ticket, :count)
      end

      it "no crea ticket con tipo de archivo inválido (.exe)" do
        expect {
          post tickets_path, params: { ticket: { original_files: [ invalid_type_file ] } }
        }.not_to change(Ticket, :count)
      end

      it "crea solo los archivos válidos cuando se mezclan válidos e inválidos" do
        expect {
          post tickets_path,
               params: { ticket: { original_files: [ valid_pdf, invalid_type_file ] } }
        }.to change(Ticket, :count).by(1)
      end
    end

    context "usuario no autenticado" do
      it "redirige a la página de login" do
        post tickets_path, params: { ticket: { original_files: [ valid_pdf ] } }

        expect(response).to redirect_to(new_session_path)
      end

      it "no crea ningún ticket" do
        expect {
          post tickets_path, params: { ticket: { original_files: [ valid_pdf ] } }
        }.not_to change(Ticket, :count)
      end
    end
  end
end
