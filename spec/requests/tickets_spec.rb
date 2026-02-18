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
    # Genera un archivo en memoria que supera los 10MB
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

      it "crea un ticket con status pending_parse al subir un PDF válido" do
        expect {
          post tickets_path, params: { ticket: { original_file: valid_pdf } }
        }.to change(Ticket, :count).by(1)

        ticket = Ticket.last
        expect(ticket.user).to eq(user)
        expect(ticket.status).to eq("pending_parse")
        expect(ticket.trip).to be_nil
        expect(ticket.original_file).to be_attached
      end

      it "crea un ticket al subir una imagen JPG válida" do
        expect {
          post tickets_path, params: { ticket: { original_file: valid_jpg } }
        }.to change(Ticket, :count).by(1)
      end

      it "responde con turbo stream en creación exitosa" do
        post tickets_path,
             params: { ticket: { original_file: valid_pdf } },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end

      it "falla y no crea ticket si no se sube archivo" do
        expect {
          post tickets_path, params: { ticket: {} }
        }.not_to change(Ticket, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "falla si el archivo supera los 10MB" do
        expect {
          post tickets_path, params: { ticket: { original_file: oversized_file } }
        }.not_to change(Ticket, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "falla con tipo de archivo inválido (.exe)" do
        expect {
          post tickets_path, params: { ticket: { original_file: invalid_type_file } }
        }.not_to change(Ticket, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "usuario no autenticado" do
      it "redirige a la página de login" do
        post tickets_path, params: { ticket: { original_file: valid_pdf } }

        expect(response).to redirect_to(new_session_path)
      end

      it "no crea ningún ticket" do
        expect {
          post tickets_path, params: { ticket: { original_file: valid_pdf } }
        }.not_to change(Ticket, :count)
      end
    end
  end
end
