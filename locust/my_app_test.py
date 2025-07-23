# my_app_test.py
from locust import HttpUser, task, between

class MyUser(HttpUser):
    wait_time = between(1, 2.5) # Her istek arasında 1 ile 2.5 saniye bekle

    @task
    def load_homepage(self):
        # Uygulamanızın ana sayfasına GET isteği gönder
        self.client.get("/")

    # İsteğe bağlı olarak başka bir endpoint ekleyebilirsiniz
    # @task
    # def load_api_endpoint(self):
    #     self.client.get("/api/data")